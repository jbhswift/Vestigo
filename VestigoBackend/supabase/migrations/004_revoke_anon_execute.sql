-- Fix: this Supabase project's default ACL (ALTER DEFAULT PRIVILEGES, visible
-- in pg_default_acl for schema public) automatically grants EXECUTE to anon,
-- authenticated, AND service_role on every newly created function. A plain
-- `REVOKE EXECUTE ... FROM PUBLIC` does not undo this, since it's a direct
-- per-role grant rather than a PUBLIC-based one — confirmed by testing
-- (has_function_privilege('anon', ...) returned true for every function in
-- migration 002 despite the FROM PUBLIC revoke already present).
--
-- Every client-facing function here requires an authenticated caller, so anon
-- must be explicitly revoked per function, every time. check_rate_limit is
-- internal-only (called only from within other SECURITY DEFINER functions)
-- so it gets both anon and authenticated revoked.

REVOKE EXECUTE ON FUNCTION create_invite() FROM anon;
REVOKE EXECUTE ON FUNCTION get_invite_preview(TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION accept_invite(TEXT) FROM anon;
REVOKE EXECUTE ON FUNCTION get_friend_library(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION push_library_snapshot(TEXT, JSONB) FROM anon;
REVOKE EXECUTE ON FUNCTION remove_friend(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION update_sharing_prefs(BOOLEAN, BOOLEAN, BOOLEAN, BOOLEAN) FROM anon;
REVOKE EXECUTE ON FUNCTION handle_new_user() FROM anon;
REVOKE EXECUTE ON FUNCTION handle_new_user() FROM authenticated;

REVOKE EXECUTE ON FUNCTION check_rate_limit(TEXT, INT, INTERVAL) FROM anon;
REVOKE EXECUTE ON FUNCTION check_rate_limit(TEXT, INT, INTERVAL) FROM authenticated;
