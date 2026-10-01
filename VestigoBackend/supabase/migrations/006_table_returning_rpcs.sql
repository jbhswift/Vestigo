-- Stage 4: normalize push_library_snapshot / get_friend_library / update_sharing_prefs to
-- RETURNS TABLE(...), matching create_invite/get_invite_preview/accept_invite.
--
-- Reason: PostgREST's response shape differs by return kind — a bare scalar (BIGINT,
-- JSONB) comes back unwrapped, and VOID comes back as an empty body — while every
-- RETURNS TABLE(...) function already confirmed working (Stage 3) comes back as a JSON
-- array of row objects. Rather than handle three different response shapes in the Swift
-- client, every RPC in this system now returns TABLE(...) so one decode path covers all
-- of them.

DROP FUNCTION push_library_snapshot(TEXT, JSONB);

CREATE FUNCTION push_library_snapshot(p_category TEXT, p_payload JSONB)
RETURNS TABLE (revision BIGINT)
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

  RETURN QUERY SELECT v_rev;
END;
$$;

REVOKE EXECUTE ON FUNCTION push_library_snapshot(TEXT, JSONB) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION push_library_snapshot(TEXT, JSONB) FROM anon;
GRANT EXECUTE ON FUNCTION push_library_snapshot(TEXT, JSONB) TO authenticated;

DROP FUNCTION get_friend_library(UUID);

CREATE FUNCTION get_friend_library(p_friend_id UUID)
RETURNS TABLE (payload JSONB)
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
    WHERE user_a = LEAST(v_uid, p_friend_id) AND user_b = GREATEST(v_uid, p_friend_id)
  ) INTO v_is_friend;

  IF NOT v_is_friend THEN
    RETURN QUERY SELECT '{}'::jsonb;
    RETURN;
  END IF;

  SELECT * INTO v_prefs FROM public.sharing_prefs WHERE user_id = p_friend_id;
  IF NOT FOUND THEN
    RETURN QUERY SELECT '{}'::jsonb;
    RETURN;
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

  RETURN QUERY SELECT v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_friend_library(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION get_friend_library(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION get_friend_library(UUID) TO authenticated;

DROP FUNCTION update_sharing_prefs(BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN);

CREATE FUNCTION update_sharing_prefs(
  p_share_watchlist BOOLEAN,
  p_share_watched BOOLEAN,
  p_share_ratings BOOLEAN,
  p_share_currently_watching BOOLEAN
)
RETURNS TABLE (ok BOOLEAN)
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

  RETURN QUERY SELECT true;
END;
$$;

REVOKE EXECUTE ON FUNCTION update_sharing_prefs(BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION update_sharing_prefs(BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN) FROM anon;
GRANT EXECUTE ON FUNCTION update_sharing_prefs(BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN) TO authenticated;
