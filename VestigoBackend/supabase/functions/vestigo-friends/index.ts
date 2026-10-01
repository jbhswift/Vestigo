// Supabase Edge Function: vestigo-friends
// Narrow, separate from vestigo-api (which stays fully anonymous for TMDb-proxy
// traffic). Everything else in the friends system (invites, accept, friend
// library reads/writes, removal, sharing prefs) is a Postgres SECURITY DEFINER
// RPC called directly by the client via supabase.rpc(...) — see
// supabase/migrations/002_friends_system.sql.
//
// This function exists only for the one operation that genuinely needs the
// service-role Admin API rather than being expressible as a plain RLS-scoped
// SQL function: deleting a user's Sign-in-with-Apple-linked account.
// auth.admin.deleteUser() cascades through every table's
// `ON DELETE CASCADE ... REFERENCES auth.users(id)` automatically — there is
// nothing else to clean up here. This is separate from and does not touch the
// user's personal movie library (local storage / iCloud KV sync), which this
// feature never had access to.
//
// Deploy with: supabase functions deploy vestigo-friends (from VestigoBackend/)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405, headers: corsHeaders })
  }

  const url = new URL(req.url)
  if (url.pathname.replace(/\/+$/, '').endsWith('delete-account') === false) {
    return new Response(JSON.stringify({ ok: false, error: 'not found' }), {
      status: 404,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  const authHeader = req.headers.get('Authorization') ?? ''
  const jwt = authHeader.replace(/^Bearer\s+/i, '')
  if (!jwt) {
    return new Response(JSON.stringify({ ok: false, error: 'missing bearer token' }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

  // Verify the caller's own session — never trust a client-supplied user id.
  const callerClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: `Bearer ${jwt}` } },
  })
  const { data: userData, error: userError } = await callerClient.auth.getUser()
  if (userError || !userData?.user) {
    return new Response(JSON.stringify({ ok: false, error: 'invalid session' }), {
      status: 401,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
  const callerId = userData.user.id

  // Service-role client, used only server-side, never shipped to the client.
  const adminClient = createClient(supabaseUrl, serviceRoleKey)

  const { error: deleteError } = await adminClient.auth.admin.deleteUser(callerId)
  if (deleteError) {
    console.error('delete-account error:', deleteError)
    return new Response(JSON.stringify({ ok: false, error: deleteError.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  return new Response(JSON.stringify({ ok: true }), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
})
