// Supabase Edge Function: report-omdb-usage
// Called by the iOS app to sync OMDb daily/total request counts to Postgres.
// Deploy with: supabase functions deploy report-omdb-usage

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

// Supabase is retiring the legacy service_role JWT in favor of the
// independently-revocable secret key (SUPABASE_SECRET_KEYS, JSON-encoded,
// keyed by key name — "default" here). Reads the new key first; falls back
// to the legacy env var only if the new one isn't present yet, so this keeps
// working across the legacy-key disable step.
function resolveSecretKey(): string {
  const raw = Deno.env.get('SUPABASE_SECRET_KEYS')
  if (raw) {
    try {
      const parsed = JSON.parse(raw)
      if (parsed.default) return parsed.default
    } catch { /* fall through to legacy */ }
  }
  return Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return new Response('Method not allowed', { status: 405, headers: corsHeaders })
  }

  let body: { report_date?: string; daily_count?: number; total_count?: number; daily_limit?: number }
  try {
    body = await req.json()
  } catch {
    return new Response(JSON.stringify({ ok: false, error: 'invalid JSON' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  const { report_date, daily_count, total_count, daily_limit } = body
  if (!report_date || daily_count == null || total_count == null) {
    return new Response(JSON.stringify({ ok: false, error: 'missing fields' }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    resolveSecretKey(),
  )

  const { error } = await supabase
    .from('omdb_usage_reports')
    .upsert(
      { report_date, daily_count, total_count, daily_limit: daily_limit ?? 1000, reported_at: new Date().toISOString() },
      { onConflict: 'report_date' },
    )

  if (error) {
    console.error('upsert error:', error)
    return new Response(JSON.stringify({ ok: false, error: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }

  return new Response(JSON.stringify({ ok: true }), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
})
