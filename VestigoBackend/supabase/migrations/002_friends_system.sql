-- Vestigo: backend-mediated friends system
-- Replaces the old CloudKit-public-database social sharing design (see
-- VestigoBackend/cloudkit-schema-backups/ for the CloudKit-side lockdown).
--
-- Design notes (see project memory "friends-social-redesign-decision" for full history):
--   * shared_library_snapshots is one row per (user_id, category), not one row with
--     multiple columns, because Postgres RLS is row-level, not column-level — a single
--     multi-column row would leak disabled categories to any friend who can read the row.
--   * No direct client INSERT on friendships/invites — only reachable via the
--     SECURITY DEFINER functions below, so a client can never fabricate a friendship or
--     forge invite state via a raw PostgREST request.
--   * library_revision_counters is incremented by the backend (push_library_snapshot),
--     never computed client-side, so two concurrent pushes can never collide on the same
--     revision number. This guarantees unambiguous *upload ordering* only — it does NOT
--     guarantee the most-recently-pushed device has the freshest data (a stale offline
--     device can still overwrite a fresher snapshot with older data; that is an accepted,
--     documented limitation, not something this migration attempts to fix).
--
-- Apply with: supabase db push (from VestigoBackend/supabase, the linked project directory)

-- ============================================================================
-- profiles
-- ============================================================================

CREATE TABLE profiles (
  user_id      UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  display_name TEXT,
  avatar_url   TEXT,
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;

-- Self-service: a user can read/update only their own profile row directly.
-- No policy grants visibility into anyone else's profile — that only happens
-- through get_invite_preview()/get_friend_library(), which return just the
-- display_name/avatar_url of a confirmed inviter/friend, never the raw table.
CREATE POLICY "profiles_select_own" ON profiles
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "profiles_update_own" ON profiles
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "profiles_insert_own" ON profiles
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- Auto-create a blank profile row the first time a user authenticates
-- (standard Supabase pattern — trigger on auth.users, not on first app action).
CREATE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  INSERT INTO public.profiles (user_id) VALUES (NEW.id);
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ============================================================================
-- invites
-- ============================================================================

CREATE TABLE invites (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  inviter_id  UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token       TEXT NOT NULL UNIQUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at  TIMESTAMPTZ NOT NULL,
  max_uses    INT NOT NULL DEFAULT 1,
  use_count   INT NOT NULL DEFAULT 0,
  revoked_at  TIMESTAMPTZ
);

CREATE INDEX invites_token_idx ON invites (token);

ALTER TABLE invites ENABLE ROW LEVEL SECURITY;
-- Deliberately zero policies: the raw table is not directly readable or writable
-- by any client role. Every operation goes through a SECURITY DEFINER function
-- below so token validation/consumption is atomic and auditable in one place.

-- ============================================================================
-- friendships
-- ============================================================================

CREATE TABLE friendships (
  user_a     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_b     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_a, user_b),
  CONSTRAINT friendships_canonical_order CHECK (user_a < user_b)
);

CREATE INDEX friendships_user_b_idx ON friendships (user_b);

ALTER TABLE friendships ENABLE ROW LEVEL SECURITY;

-- A user may see their own friendship rows directly (harmless — it's just
-- "who am I friends with", not friend-only content). No INSERT/UPDATE/DELETE
-- policy: creation only via accept_invite(), removal only via remove_friend().
CREATE POLICY "friendships_select_own" ON friendships
  FOR SELECT TO authenticated
  USING (user_a = auth.uid() OR user_b = auth.uid());

-- ============================================================================
-- sharing_prefs
-- ============================================================================

CREATE TABLE sharing_prefs (
  user_id                    UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  share_watchlist            BOOLEAN NOT NULL DEFAULT FALSE,
  share_watched              BOOLEAN NOT NULL DEFAULT FALSE,
  share_ratings              BOOLEAN NOT NULL DEFAULT FALSE,
  share_currently_watching   BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at                 TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE sharing_prefs ENABLE ROW LEVEL SECURITY;

-- Self-service read of your own prefs is fine directly via RLS. Writes go
-- through update_sharing_prefs() instead of a raw UPDATE policy, because
-- toggling a category off must also synchronously clear that category's
-- row in shared_library_snapshots (data minimization), which a plain
-- single-table UPDATE policy cannot express.
CREATE POLICY "sharing_prefs_select_own" ON sharing_prefs
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- ============================================================================
-- shared_library_snapshots — one row per (user_id, category), see notes above
-- ============================================================================

CREATE TABLE shared_library_snapshots (
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  category        TEXT NOT NULL CHECK (category IN ('watchlist', 'watched', 'ratings', 'currently_watching')),
  payload         JSONB NOT NULL,
  source_revision BIGINT NOT NULL,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (user_id, category)
);

ALTER TABLE shared_library_snapshots ENABLE ROW LEVEL SECURITY;
-- Deliberately zero policies — not even an owner-read policy. The only path
-- to this data is get_friend_library() (for friends) and push_library_snapshot()
-- (for the owner's own writes). This is the backstop for the category-leak
-- fix: even if get_friend_library() had a bug, a direct PostgREST SELECT
-- against this table returns nothing for anyone, full stop.

-- ============================================================================
-- library_revision_counters — backend-issued, never client-computed
-- ============================================================================

CREATE TABLE library_revision_counters (
  user_id         UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  current_revision BIGINT NOT NULL DEFAULT 0
);

ALTER TABLE library_revision_counters ENABLE ROW LEVEL SECURITY;
-- No policies at all — purely internal bookkeeping for push_library_snapshot().

-- ============================================================================
-- rate_limits — atomic Postgres counter, no external vendor at current scale
-- ============================================================================

CREATE TABLE rate_limits (
  key         TEXT PRIMARY KEY,
  window_start TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  count       INT NOT NULL DEFAULT 1
);

ALTER TABLE rate_limits ENABLE ROW LEVEL SECURITY;
-- No policies — only touched internally by the functions below via SECURITY DEFINER.

-- Returns TRUE if the call should proceed, FALSE if the caller has exceeded
-- p_max calls within the current p_window. Atomic via a single upsert.
CREATE FUNCTION check_rate_limit(p_key TEXT, p_max INT, p_window INTERVAL)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_count INT;
BEGIN
  INSERT INTO public.rate_limits (key, window_start, count)
  VALUES (p_key, now(), 1)
  ON CONFLICT (key) DO UPDATE SET
    count = CASE
      WHEN public.rate_limits.window_start < now() - p_window THEN 1
      ELSE public.rate_limits.count + 1
    END,
    window_start = CASE
      WHEN public.rate_limits.window_start < now() - p_window THEN now()
      ELSE public.rate_limits.window_start
    END
  RETURNING count INTO v_count;

  RETURN v_count <= p_max;
END;
$$;

REVOKE EXECUTE ON FUNCTION check_rate_limit(TEXT, INT, INTERVAL) FROM PUBLIC;
-- Not granted to authenticated either — it's an internal helper called only
-- from within other SECURITY DEFINER functions in this file, never directly.

-- ============================================================================
-- create_invite()
-- ============================================================================

CREATE FUNCTION create_invite()
RETURNS TABLE (token TEXT, expires_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_token TEXT;
  v_expires TIMESTAMPTZ := now() + interval '7 days';
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  IF NOT public.check_rate_limit('create_invite:' || v_uid::text, 20, interval '1 hour') THEN
    RAISE EXCEPTION 'rate limit exceeded';
  END IF;

  v_token := encode(gen_random_bytes(24), 'base64');
  v_token := replace(replace(replace(v_token, '/', '_'), '+', '-'), '=', '');

  INSERT INTO public.invites (inviter_id, token, expires_at, max_uses)
  VALUES (v_uid, v_token, v_expires, 1);

  RETURN QUERY SELECT v_token, v_expires;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_invite() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_invite() TO authenticated;

-- ============================================================================
-- get_invite_preview(token)
-- ============================================================================

CREATE FUNCTION get_invite_preview(p_token TEXT)
RETURNS TABLE (display_name TEXT, avatar_url TEXT, valid BOOLEAN)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_inviter UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  IF NOT public.check_rate_limit('preview:' || v_uid::text, 30, interval '1 hour') THEN
    RAISE EXCEPTION 'rate limit exceeded';
  END IF;

  SELECT i.inviter_id INTO v_inviter
  FROM public.invites i
  WHERE i.token = p_token
    AND i.revoked_at IS NULL
    AND i.expires_at > now()
    AND i.use_count < i.max_uses;

  IF v_inviter IS NULL THEN
    RETURN QUERY SELECT NULL::TEXT, NULL::TEXT, FALSE;
    RETURN;
  END IF;

  RETURN QUERY
  SELECT p.display_name, p.avatar_url, TRUE
  FROM public.profiles p
  WHERE p.user_id = v_inviter;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_invite_preview(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_invite_preview(TEXT) TO authenticated;

-- ============================================================================
-- accept_invite(token) — atomic, single-use, mutual by construction
-- ============================================================================

CREATE FUNCTION accept_invite(p_token TEXT)
RETURNS TABLE (friend_user_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_invite public.invites%ROWTYPE;
  v_a UUID;
  v_b UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  IF NOT public.check_rate_limit('accept_invite:' || v_uid::text, 20, interval '1 hour') THEN
    RAISE EXCEPTION 'rate limit exceeded';
  END IF;

  -- Row lock so two concurrent accepts on the same token can't both succeed.
  SELECT * INTO v_invite
  FROM public.invites
  WHERE token = p_token
    AND revoked_at IS NULL
    AND expires_at > now()
    AND use_count < max_uses
  FOR UPDATE;

  IF v_invite.id IS NULL THEN
    RAISE EXCEPTION 'invite invalid, expired, or already used';
  END IF;

  IF v_invite.inviter_id = v_uid THEN
    RAISE EXCEPTION 'cannot accept your own invite';
  END IF;

  v_a := LEAST(v_invite.inviter_id, v_uid);
  v_b := GREATEST(v_invite.inviter_id, v_uid);

  INSERT INTO public.friendships (user_a, user_b)
  VALUES (v_a, v_b)
  ON CONFLICT (user_a, user_b) DO NOTHING;

  UPDATE public.invites
  SET use_count = use_count + 1,
      revoked_at = CASE WHEN use_count + 1 >= max_uses THEN now() ELSE revoked_at END
  WHERE id = v_invite.id;

  RETURN QUERY SELECT v_invite.inviter_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION accept_invite(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION accept_invite(TEXT) TO authenticated;

-- ============================================================================
-- get_friend_library(friend_id) — only enabled categories, only for confirmed friends
-- ============================================================================

CREATE FUNCTION get_friend_library(p_friend_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_is_friend BOOLEAN;
  v_prefs public.sharing_prefs%ROWTYPE;
  v_result JSONB := '{}'::jsonb;
  v_row RECORD;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.friendships
    WHERE (user_a = LEAST(v_uid, p_friend_id) AND user_b = GREATEST(v_uid, p_friend_id))
  ) INTO v_is_friend;

  IF NOT v_is_friend THEN
    RETURN '{}'::jsonb;
  END IF;

  SELECT * INTO v_prefs FROM public.sharing_prefs WHERE user_id = p_friend_id;
  IF NOT FOUND THEN
    RETURN '{}'::jsonb;
  END IF;

  FOR v_row IN
    SELECT category, payload FROM public.shared_library_snapshots
    WHERE user_id = p_friend_id
      AND (
        (category = 'watchlist' AND v_prefs.share_watchlist) OR
        (category = 'watched' AND v_prefs.share_watched) OR
        (category = 'ratings' AND v_prefs.share_ratings) OR
        (category = 'currently_watching' AND v_prefs.share_currently_watching)
      )
  LOOP
    v_result := v_result || jsonb_build_object(v_row.category, v_row.payload);
  END LOOP;

  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_friend_library(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION get_friend_library(UUID) TO authenticated;

-- ============================================================================
-- push_library_snapshot(category, payload) — backend-issued revision number
-- ============================================================================

CREATE FUNCTION push_library_snapshot(p_category TEXT, p_payload JSONB)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_rev BIGINT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  IF p_category NOT IN ('watchlist', 'watched', 'ratings', 'currently_watching') THEN
    RAISE EXCEPTION 'invalid category';
  END IF;

  INSERT INTO public.library_revision_counters (user_id, current_revision)
  VALUES (v_uid, 1)
  ON CONFLICT (user_id) DO UPDATE
    SET current_revision = public.library_revision_counters.current_revision + 1
  RETURNING current_revision INTO v_rev;

  INSERT INTO public.shared_library_snapshots (user_id, category, payload, source_revision)
  VALUES (v_uid, p_category, p_payload, v_rev)
  ON CONFLICT (user_id, category) DO UPDATE SET
    payload = excluded.payload,
    source_revision = excluded.source_revision,
    updated_at = now()
  WHERE public.shared_library_snapshots.source_revision < excluded.source_revision;

  RETURN v_rev;
END;
$$;

REVOKE EXECUTE ON FUNCTION push_library_snapshot(TEXT, JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION push_library_snapshot(TEXT, JSONB) TO authenticated;

-- ============================================================================
-- remove_friend(friend_id) — bidirectional, unilateral
-- ============================================================================

CREATE FUNCTION remove_friend(p_friend_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  DELETE FROM public.friendships
  WHERE user_a = LEAST(v_uid, p_friend_id) AND user_b = GREATEST(v_uid, p_friend_id);
END;
$$;

REVOKE EXECUTE ON FUNCTION remove_friend(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION remove_friend(UUID) TO authenticated;

-- ============================================================================
-- update_sharing_prefs(...) — also clears snapshot data for categories turned off
-- ============================================================================

CREATE FUNCTION update_sharing_prefs(
  p_share_watchlist BOOLEAN,
  p_share_watched BOOLEAN,
  p_share_ratings BOOLEAN,
  p_share_currently_watching BOOLEAN
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  INSERT INTO public.sharing_prefs (user_id, share_watchlist, share_watched, share_ratings, share_currently_watching)
  VALUES (v_uid, p_share_watchlist, p_share_watched, p_share_ratings, p_share_currently_watching)
  ON CONFLICT (user_id) DO UPDATE SET
    share_watchlist = excluded.share_watchlist,
    share_watched = excluded.share_watched,
    share_ratings = excluded.share_ratings,
    share_currently_watching = excluded.share_currently_watching,
    updated_at = now();

  IF NOT p_share_watchlist THEN
    DELETE FROM public.shared_library_snapshots WHERE user_id = v_uid AND category = 'watchlist';
  END IF;
  IF NOT p_share_watched THEN
    DELETE FROM public.shared_library_snapshots WHERE user_id = v_uid AND category = 'watched';
  END IF;
  IF NOT p_share_ratings THEN
    DELETE FROM public.shared_library_snapshots WHERE user_id = v_uid AND category = 'ratings';
  END IF;
  IF NOT p_share_currently_watching THEN
    DELETE FROM public.shared_library_snapshots WHERE user_id = v_uid AND category = 'currently_watching';
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION update_sharing_prefs(BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION update_sharing_prefs(BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN) TO authenticated;
