// Supabase Edge Function: get-app-config
// Returns analytics SDK keys stored as Supabase secrets so they never live in the binary.
//
// Set secrets with:
//   supabase secrets set POSTHOG_API_KEY=phc_xxxxxxxxxx
//   supabase secrets set POSTHOG_HOST=https://us.i.posthog.com
//   supabase secrets set SENTRY_DSN=https://xxxxxxxxxx@o0.ingest.sentry.io/0
//
// Deploy with:
//   supabase functions deploy get-app-config

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  const posthogKey = Deno.env.get('POSTHOG_API_KEY') ?? ''
  const posthogHost = Deno.env.get('POSTHOG_HOST') ?? 'https://us.i.posthog.com'
  const sentryDsn = Deno.env.get('SENTRY_DSN') ?? ''

  return new Response(
    JSON.stringify({ ok: true, posthogKey, posthogHost, sentryDsn }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  )
})
