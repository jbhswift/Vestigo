-- Stage 4: friend list support.
--
-- Featured/Excited-For are, like the old CloudKit system, always visible to confirmed
-- friends regardless of the watchlist/watched/ratings/currently-watching sharing toggles
-- (CloudPublicSync.swift wrote featuredPayload/excitedForPayload unconditionally, outside
-- the `if sharing` gate) — so they live directly on `profiles`, not as a gated category in
-- shared_library_snapshots.
ALTER TABLE profiles ADD COLUMN featured_items JSONB NOT NULL DEFAULT '[]'::jsonb;
ALTER TABLE profiles ADD COLUMN excited_for_items JSONB NOT NULL DEFAULT '[]'::jsonb;

-- get_my_friends() — the only way a client can ever see another user's display_name/
-- avatar_url/featured/excited-for; profiles' own RLS policy only allows reading your own
-- row, so this SECURITY DEFINER function (which re-validates the friendship itself via
-- the join, not just trusting the caller) is the sole path to a friend's identity fields.
CREATE FUNCTION get_my_friends()
RETURNS TABLE (
  friend_id UUID,
  display_name TEXT,
  avatar_url TEXT,
  featured_items JSONB,
  excited_for_items JSONB
)
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

  RETURN QUERY
  SELECT p.user_id, p.display_name, p.avatar_url, p.featured_items, p.excited_for_items
  FROM public.friendships f
  JOIN public.profiles p ON p.user_id = (CASE WHEN f.user_a = v_uid THEN f.user_b ELSE f.user_a END)
  WHERE f.user_a = v_uid OR f.user_b = v_uid;
END;
$$;

REVOKE EXECUTE ON FUNCTION get_my_friends() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION get_my_friends() FROM anon;
GRANT EXECUTE ON FUNCTION get_my_friends() TO authenticated;
