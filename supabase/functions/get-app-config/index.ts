// Supabase Edge Function: get-app-config
// Returns analytics SDK keys stored as Supabase secrets so they never live in the binary.
//
// Set secrets with:
//   supabase secrets set POSTHOG_API_KEY=phc_xxxxxxxxxx
//   supabase secrets set POSTHOG_HOST=https://us.i.posthog.com
//   supabase secrets set SENTRY_DSN=https://xxxxxxxxxx@o0.ingest.sentry.io/0
//   supabase secrets set SENTRY_APP_HANG_TIMEOUT_SECONDS=5
//   supabase secrets set SENTRY_REPORT_NON_FULLY_BLOCKING_APP_HANGS=false
//
// Deploy with:
//   supabase functions deploy get-app-config

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const parsePositiveNumber = (value: string | undefined): number | undefined => {
  if (!value) return undefined

  const numberValue = Number(value)
  return Number.isFinite(numberValue) && numberValue > 0 ? numberValue : undefined
}

const parseBoolean = (value: string | undefined): boolean | undefined => {
  if (!value) return undefined

  const normalized = value.trim().toLowerCase()
  if (normalized === 'true') return true
  if (normalized === 'false') return false

  return undefined
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  const posthogKey = Deno.env.get('POSTHOG_API_KEY') ?? ''
  const posthogHost = Deno.env.get('POSTHOG_HOST') ?? 'https://us.i.posthog.com'
  const sentryDsn = Deno.env.get('SENTRY_DSN') ?? ''
  const sentryAppHangTimeoutSeconds = parsePositiveNumber(Deno.env.get('SENTRY_APP_HANG_TIMEOUT_SECONDS'))
  const sentryReportNonFullyBlockingAppHangs = parseBoolean(Deno.env.get('SENTRY_REPORT_NON_FULLY_BLOCKING_APP_HANGS'))

  return new Response(
    JSON.stringify({
      ok: true,
      posthogKey,
      posthogHost,
      sentryDsn,
      sentryAppHangTimeoutSeconds,
      sentryReportNonFullyBlockingAppHangs,
    }),
    { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  )
})
