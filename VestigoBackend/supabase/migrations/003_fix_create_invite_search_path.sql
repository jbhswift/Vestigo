-- Fix: create_invite() calls gen_random_bytes(), which lives in the
-- `extensions` schema (pgcrypto), not pg_catalog. With SET search_path = ''
-- (intentional, for search-path-hijacking hardening per the SECURITY DEFINER
-- checklist), unqualified calls to anything outside pg_catalog don't resolve.
-- Fix is to schema-qualify the call rather than relax search_path.

CREATE OR REPLACE FUNCTION create_invite()
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

  v_token := encode(extensions.gen_random_bytes(24), 'base64');
  v_token := replace(replace(replace(v_token, '/', '_'), '+', '-'), '=', '');

  INSERT INTO public.invites (inviter_id, token, expires_at, max_uses)
  VALUES (v_uid, v_token, v_expires, 1);

  RETURN QUERY SELECT v_token, v_expires;
END;
$$;

REVOKE EXECUTE ON FUNCTION create_invite() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION create_invite() TO authenticated;
