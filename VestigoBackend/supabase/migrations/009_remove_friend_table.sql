-- Stage 5: normalize remove_friend to RETURNS TABLE(ok BOOLEAN), matching every other
-- client-facing RPC in this system (see migration 006's rationale) — a bare VOID function
-- comes back from PostgREST as an empty body, which doesn't fit the single [Row]-decode
-- path SupabaseRPCClient.callTable uses for everything else.

DROP FUNCTION remove_friend(UUID);

CREATE FUNCTION remove_friend(p_friend_id UUID)
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

  DELETE FROM public.friendships
  WHERE user_a = LEAST(v_uid, p_friend_id) AND user_b = GREATEST(v_uid, p_friend_id);

  RETURN QUERY SELECT true;
END;
$$;

REVOKE EXECUTE ON FUNCTION remove_friend(UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION remove_friend(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION remove_friend(UUID) TO authenticated;
