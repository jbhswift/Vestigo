-- Stage 4 live-test bug: get_friend_library's RETURNS TABLE output column `payload`
-- shadows shared_library_snapshots.payload inside the function's own FOR-loop query,
-- which plpgsql rejects as an ambiguous column reference (42702) rather than silently
-- guessing — caught only now because migrations 006/007 were never re-exercised with a
-- real row to iterate over. Fix: qualify the column with a table alias.

DROP FUNCTION get_friend_library(UUID);

CREATE FUNCTION get_friend_library(p_friend_id UUID)
RETURNS TABLE (
  payload JSONB,
  share_watchlist BOOLEAN,
  share_watched BOOLEAN,
  share_ratings BOOLEAN,
  share_currently_watching BOOLEAN
)
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
    RETURN QUERY SELECT '{}'::jsonb, false, false, false, false;
    RETURN;
  END IF;

  SELECT * INTO v_prefs FROM public.sharing_prefs WHERE user_id = p_friend_id;
  IF NOT FOUND THEN
    RETURN QUERY SELECT '{}'::jsonb, false, false, false, false;
    RETURN;
  END IF;

  FOR v_row IN
    SELECT s.category, s.payload FROM public.shared_library_snapshots s
    WHERE s.user_id = p_friend_id
      AND (
        (s.category = 'watchlist' AND v_prefs.share_watchlist) OR
        (s.category = 'watched' AND v_prefs.share_watched) OR
        (s.category = 'ratings' AND v_prefs.share_ratings) OR
        (s.category = 'currently_watching' AND v_prefs.share_currently_watching)
      )
  LOOP
    v_result := v_result || jsonb_build_object(v_row.category, v_row.payload);
  END LOOP;

  RETURN QUERY SELECT v_result, v_prefs.share_watchlist, v_prefs.share_watched, v_prefs.share_ratings, v_prefs.share_currently_watching;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_friend_library(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION get_friend_library(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION get_friend_library(UUID) TO authenticated;
