import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { unstable_cache } from 'next/cache'

export const dynamic = 'force-dynamic'

const POSTHOG_HOST = process.env.POSTHOG_HOST ?? 'https://us.posthog.com'
const PROJECT_ID = process.env.POSTHOG_PROJECT_ID!
const PERSONAL_KEY = process.env.POSTHOG_PERSONAL_API_KEY!

export interface QuotaItem {
  key: string
  name: string
  limit: number | null
  limitUnit: 'calls' | 'USD' | 'events' | 'errors'
  period: 'day' | 'month' | 'second'
  used: number | null
  allTime: number | null
  resetsAt: string | null  // ISO timestamp
  dataSource: 'live' | 'static'
  unconfigured?: boolean
  hidden?: boolean
  note?: string
  dashboardUrl: string
}

function nextDailyReset(): string {
  const t = new Date()
  t.setUTCDate(t.getUTCDate() + 1)
  t.setUTCHours(0, 0, 0, 0)
  return t.toISOString()
}

function nextMonthlyReset(): string {
  const t = new Date()
  t.setUTCMonth(t.getUTCMonth() + 1, 1)
  t.setUTCHours(0, 0, 0, 0)
  return t.toISOString()
}

function endOfMonthReset(): string {
  const t = new Date()
  // last moment of the current month
  t.setUTCMonth(t.getUTCMonth() + 1, 0)
  t.setUTCHours(23, 59, 59, 0)
  return t.toISOString()
}

async function hogql(query: string): Promise<unknown[][]> {
  const res = await fetch(`${POSTHOG_HOST}/api/projects/${PROJECT_ID}/query/`, {
    method: 'POST',
    headers: { Authorization: `Bearer ${PERSONAL_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ query: { kind: 'HogQLQuery', query } }),
    next: { revalidate: 60 },
  })
  if (!res.ok) throw new Error(`PostHog ${res.status}`)
  return (await res.json()).results as unknown[][]
}

// Fetch API call counts from PostHog for the current calendar month, keyed by service.
// backend_api_call = fired by Supabase when calling external APIs (preferred, more accurate).
// api_call = fired by iOS when requesting from the backend (fallback for services without backend tracking).
async function apiCallCountsByService(): Promise<Record<string, number>> {
  const monthStart = new Date(Date.UTC(new Date().getUTCFullYear(), new Date().getUTCMonth(), 1))
    .toISOString()
    .split('T')[0]
  const rows = await hogql(`
    SELECT
      properties.service AS service,
      countIf(event = 'backend_api_call') AS backend_calls,
      countIf(event = 'api_call') AS ios_calls
    FROM events
    WHERE event IN ('api_call', 'backend_api_call')
      AND toDate(timestamp) >= '${monthStart}'
    GROUP BY service
    ORDER BY backend_calls DESC, ios_calls DESC
  `)
  const counts: Record<string, number> = {}
  for (const [service, backendCalls, iosCalls] of rows) {
    if (typeof service === 'string') {
      const backend = Number(backendCalls)
      const ios = Number(iosCalls)
      // Prefer backend count (actual external API calls); fall back to iOS count
      counts[service] = backend > 0 ? backend : ios
    }
  }
  return counts
}

// Fetch server-side KV-measured call counts from the Supabase edge function.
// This is the authoritative source for providers without a native usage API.
async function vestigoServiceCounts(): Promise<Record<string, number>> {
  const supabaseUrl = process.env.SUPABASE_URL
  const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!supabaseUrl || !supabaseKey) return {}
  const res = await fetch(`${supabaseUrl}/functions/v1/vestigo-api/service-usage?days=30`, {
    headers: { Authorization: `Bearer ${supabaseKey}` },
    next: { revalidate: 300 },
  })
  if (!res.ok) return {}
  const json = await res.json()
  return (json.counts as Record<string, number>) ?? {}
}

export async function GET() {
  const quotas: QuotaItem[] = []

  // Fetch both data sources in parallel — Vestigo KV is preferred; PostHog is fallback
  let phCounts: Record<string, number> = {}
  let kvCounts: Record<string, number> = {}
  try {
    ;[phCounts, kvCounts] = await Promise.all([
      apiCallCountsByService().catch(() => ({})),
      vestigoServiceCounts().catch(() => ({})),
    ])
  } catch { /* non-fatal */ }

  // Helper: pick Vestigo KV count if available, fall back to PostHog
  function bestCount(service: string): number | null {
    if (kvCounts[service] != null) return kvCounts[service]
    if (phCounts[service] != null) return phCounts[service]
    return null
  }

  // ── OMDb (live via Supabase) ─────────────────────────────────────────────
  try {
    const supa =
      process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY
        ? createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY)
        : null
    const { data } = supa
      ? await supa
          .from('omdb_usage_reports')
          .select('daily_count, total_count, daily_limit')
          .order('report_date', { ascending: false })
          .limit(1)
          .single()
      : { data: null }

    quotas.push({
      key: 'omdb', name: 'OMDb',
      limit: null, limitUnit: 'calls', period: 'day',
      used: null, allTime: null,
      resetsAt: nextDailyReset(),
      dataSource: 'static',
      note: 'Currently per-user key — shared quota coming soon',
      dashboardUrl: 'https://www.omdbapi.com/apikey.aspx',
    })
  } catch {
    quotas.push({
      key: 'omdb', name: 'OMDb',
      limit: null, limitUnit: 'calls', period: 'day',
      used: null, allTime: null, resetsAt: nextDailyReset(),
      dataSource: 'static',
      note: 'Currently per-user key — shared quota coming soon',
      dashboardUrl: 'https://www.omdbapi.com/apikey.aspx',
    })
  }

  // ── Watchmode (live via /v1/status/) ────────────────────────────────────
  // unstable_cache is used here because force-dynamic disables Next.js fetch
  // caching, which would otherwise cause a 429 on every dashboard load.
  const watchmodeKey = process.env.WATCHMODE_API_KEY
  if (watchmodeKey) {
    try {
      const fetchWatchmodeStatus = unstable_cache(
        async (apiKey: string) => {
          const res = await fetch(`https://api.watchmode.com/v1/status/?apiKey=${apiKey}`)
          if (!res.ok) throw new Error(`HTTP ${res.status}`)
          return res.json() as Promise<{
            account_calls_used?: number
            account_calls_limit?: number
            quota_reset_datetime_utc?: string
          }>
        },
        ['watchmode-status'],
        { revalidate: 3600 }
      )
      const wm = await fetchWatchmodeStatus(watchmodeKey)
      const wmUsed: number | null = wm.account_calls_used ?? null
      const wmLimit: number | null = wm.account_calls_limit ?? null
      const wmResetRaw: string | null = wm.quota_reset_datetime_utc ?? null
      const wmResetsAt = wmResetRaw ? new Date(wmResetRaw).toISOString() : nextMonthlyReset()
      quotas.push({
        key: 'watchmode', name: 'Watchmode',
        limit: wmLimit, limitUnit: 'calls', period: 'month',
        used: wmUsed, allTime: null, resetsAt: wmResetsAt,
        dataSource: 'live',
        dashboardUrl: 'https://api.watchmode.com/',
      })
    } catch (e) {
      quotas.push({
        key: 'watchmode', name: 'Watchmode',
        limit: null, limitUnit: 'calls', period: 'month',
        used: bestCount('watchmode'), allTime: null, resetsAt: nextMonthlyReset(),
        dataSource: 'live',
        note: `Status API error: ${String(e)} — count from Vestigo KV.`,
        dashboardUrl: 'https://api.watchmode.com/',
      })
    }
  } else {
    quotas.push({
      key: 'watchmode', name: 'Watchmode',
      limit: null, limitUnit: 'calls', period: 'month',
      used: null, allTime: null, resetsAt: nextMonthlyReset(),
      dataSource: 'static', unconfigured: true,
      dashboardUrl: 'https://api.watchmode.com/',
    })
  }

  // ── Brandfetch (live via /v2/me) ─────────────────────────────────────────
  const brandfetchKey = process.env.BRANDFETCH_CLIENT_ID
  if (brandfetchKey) {
    try {
      const bfRes = await fetch('https://api.brandfetch.io/v2/me', {
        headers: { Authorization: `Bearer ${brandfetchKey}` },
        next: { revalidate: 300 },
      })
      if (!bfRes.ok) throw new Error(`HTTP ${bfRes.status}`)
      const bf = await bfRes.json()
      const bfUsed: number | null = bf.requests?.used ?? bf.quota?.used ?? null
      const bfLimit: number | null = bf.requests?.limit ?? bf.quota?.limit ?? 1_000_000
      const bfResetRaw: string | null = bf.requests?.resetsAt ?? bf.quota?.resetsAt ?? null
      const bfResetsAt = bfResetRaw ? new Date(bfResetRaw).toISOString() : endOfMonthReset()
      quotas.push({
        key: 'brandfetch', name: 'Brandfetch',
        limit: bfLimit, limitUnit: 'calls', period: 'month',
        used: bfUsed, allTime: null, resetsAt: bfResetsAt,
        dataSource: 'live',
        dashboardUrl: 'https://brandfetch.com/dashboard',
      })
    } catch (e) {
      quotas.push({
        key: 'brandfetch', name: 'Brandfetch',
        limit: 1_000_000, limitUnit: 'calls', period: 'month',
        used: bestCount('brandfetch'), allTime: null, resetsAt: endOfMonthReset(),
        dataSource: 'live',
        note: `API error: ${String(e)} — count from PostHog.`,
        dashboardUrl: 'https://brandfetch.com/dashboard',
      })
    }
  } else {
    quotas.push({
      key: 'brandfetch', name: 'Brandfetch',
      limit: 1_000_000, limitUnit: 'calls', period: 'month',
      used: bestCount('brandfetch'), allTime: null, resetsAt: endOfMonthReset(),
      dataSource: phCounts['brandfetch'] != null ? 'live' : 'static',
      unconfigured: true,
      note: 'Add BRANDFETCH_CLIENT_ID to Vercel env vars.',
      dashboardUrl: 'https://brandfetch.com/dashboard',
    })
  }

  // ── OpenRouter (call count from Vestigo KV; spend from provider API as note) ──
  const openrouterKey = process.env.OPENROUTER_API_KEY
  if (openrouterKey) {
    let spendNote = 'Describe It only — free models.'
    try {
      const res = await fetch('https://openrouter.ai/api/v1/auth/key', {
        headers: { Authorization: `Bearer ${openrouterKey}` },
        next: { revalidate: 300 },
      })
      if (res.ok) {
        const d = await res.json()
        const spend = d.data?.usage != null ? Math.round(d.data.usage * 10000) / 10000 : null
        if (spend != null && spend > 0) spendNote = `Describe It only. Spend: $${spend}`
      }
    } catch { /* non-fatal — spend note stays default */ }
    quotas.push({
      key: 'openrouter', name: 'OpenRouter',
      limit: null, limitUnit: 'calls', period: 'month',
      used: bestCount('openrouter'),
      allTime: null,
      resetsAt: nextMonthlyReset(),
      dataSource: 'live',
      note: spendNote,
      dashboardUrl: 'https://openrouter.ai/settings/keys',
    })
  } else {
    quotas.push({
      key: 'openrouter', name: 'OpenRouter',
      limit: null, limitUnit: 'calls', period: 'month',
      used: bestCount('openrouter'), allTime: null, resetsAt: nextMonthlyReset(),
      dataSource: 'static', unconfigured: true,
      note: 'Describe It only — key not configured.',
      dashboardUrl: 'https://openrouter.ai/settings/keys',
    })
  }

  // ── OpenRouter backup ─────────────────────────────────────────────────────
  const openrouterBackupKey = process.env.OPENROUTER_BACKUP_KEY
  if (openrouterBackupKey) {
    let backupSpendNote = 'Fallback key — free models.'
    try {
      const res = await fetch('https://openrouter.ai/api/v1/auth/key', {
        headers: { Authorization: `Bearer ${openrouterBackupKey}` },
        next: { revalidate: 300 },
      })
      if (res.ok) {
        const d = await res.json()
        const spend = d.data?.usage != null ? Math.round(d.data.usage * 10000) / 10000 : null
        if (spend != null && spend > 0) backupSpendNote = `Fallback key. Spend: $${spend}`
      }
    } catch { /* non-fatal */ }
    quotas.push({
      key: 'openrouter_backup', name: 'OpenRouter (backup)',
      limit: null,
      limitUnit: 'calls', period: 'month',
      used: null,
      allTime: null,
      resetsAt: nextMonthlyReset(),
      dataSource: 'live',
      note: backupSpendNote,
      dashboardUrl: 'https://openrouter.ai/settings/keys',
    })
  }

  // ── Groq (hidden — not actively used) ────────────────────────────────────
  quotas.push({
    key: 'groq', name: 'Groq',
    limit: null, limitUnit: 'calls', period: 'month',
    used: bestCount('groq'), allTime: null, resetsAt: nextMonthlyReset(),
    dataSource: process.env.GROQ_API_KEY ? 'live' : 'static',
    hidden: true,
    note: process.env.GROQ_API_KEY ? 'No usage API — count from PostHog.' : 'Key not configured.',
    dashboardUrl: 'https://console.groq.com/usage',
  })

  // ── Cerebras (hidden — not actively used) ─────────────────────────────────
  quotas.push({
    key: 'cerebras', name: 'Cerebras',
    limit: null, limitUnit: 'calls', period: 'month',
    used: bestCount('cerebras'), allTime: null, resetsAt: nextMonthlyReset(),
    dataSource: process.env.CEREBRAS_API_KEY ? 'live' : 'static',
    hidden: true,
    note: process.env.CEREBRAS_API_KEY ? 'No usage API — count from PostHog.' : 'Key not configured.',
    dashboardUrl: 'https://cloud.cerebras.ai/',
  })

  // ── TasteDive (hidden — iOS client has this disabled) ─────────────────────
  quotas.push({
    key: 'tastedive', name: 'TasteDive',
    limit: null, limitUnit: 'calls', period: 'month',
    used: bestCount('tastedive'), allTime: null, resetsAt: nextMonthlyReset(),
    dataSource: process.env.TASTEDIVE_API_KEY ? 'live' : 'static',
    hidden: true,
    note: 'iOS client disabled — key configured but not actively used.',
    dashboardUrl: 'https://tastedive.com/read/api',
  })

  // ── PostHog (live – events this calendar month) ──────────────────────────
  try {
    const now = new Date()
    const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1))
      .toISOString()
      .split('T')[0]
    const rows = await hogql(
      `SELECT count() AS total FROM events WHERE toDate(timestamp) >= '${monthStart}'`
    )
    quotas.push({
      key: 'posthog', name: 'PostHog',
      limit: 1_000_000, limitUnit: 'events', period: 'month',
      used: rows[0] ? Number(rows[0][0]) : null,
      allTime: null,
      resetsAt: nextMonthlyReset(),
      dataSource: 'live',
      dashboardUrl: 'https://us.posthog.com',
    })
  } catch {
    quotas.push({
      key: 'posthog', name: 'PostHog',
      limit: 1_000_000, limitUnit: 'events', period: 'month',
      used: null, allTime: null, resetsAt: nextMonthlyReset(),
      dataSource: 'static', dashboardUrl: 'https://us.posthog.com',
    })
  }

  // ── TMDb ─────────────────────────────────────────────────────────────────
  quotas.push({
    key: 'tmdb', name: 'TMDb',
    limit: null, limitUnit: 'calls', period: 'month',
    used: bestCount('tmdb'), allTime: null, resetsAt: nextMonthlyReset(),
    dataSource: 'live',
    note: 'No monthly limit. Rate-limited to ~40 req/10s. Server-measured (30d).',
    dashboardUrl: 'https://www.themoviedb.org/settings/api',
  })

  // ── TVDB ─────────────────────────────────────────────────────────────────
  quotas.push({
    key: 'tvdb', name: 'TVDB',
    limit: null, limitUnit: 'calls', period: 'month',
    used: bestCount('tvdb'), allTime: null, resetsAt: nextMonthlyReset(),
    dataSource: 'live',
    note: 'Server-measured (30d). Franchise lookups can use 1–80 calls each.',
    dashboardUrl: 'https://thetvdb.com/dashboard',
  })

  // ── AMC Theatres ─────────────────────────────────────────────────────────
  quotas.push({
    key: 'amc', name: 'AMC Theatres',
    limit: null, limitUnit: 'calls', period: 'month',
    used: bestCount('amc'), allTime: null, resetsAt: nextMonthlyReset(),
    dataSource: 'live',
    note: 'Partner API. Server-measured (30d).',
    dashboardUrl: 'https://api.amctheatres.com',
  })

  // ── Wikidata ──────────────────────────────────────────────────────────────
  quotas.push({
    key: 'wikidata', name: 'Wikidata',
    limit: null, limitUnit: 'calls', period: 'month',
    used: bestCount('wikidata'), allTime: null, resetsAt: nextMonthlyReset(),
    dataSource: 'live',
    note: 'Free SPARQL. 60 req/min IP limit. Server-measured (30d).',
    dashboardUrl: 'https://query.wikidata.org/',
  })

  // ── YouTube (short detection) ─────────────────────────────────────────────
  quotas.push({
    key: 'youtube', name: 'YouTube',
    limit: null, limitUnit: 'calls', period: 'month',
    used: bestCount('youtube'), allTime: null, resetsAt: nextMonthlyReset(),
    dataSource: 'live',
    note: 'Shorts detection only. Server-measured (30d).',
    dashboardUrl: 'https://console.cloud.google.com/',
  })

  // ── Wikipedia ─────────────────────────────────────────────────────────────
  quotas.push({
    key: 'wikipedia', name: 'Wikipedia',
    limit: null, limitUnit: 'calls', period: 'month',
    used: bestCount('wikipedia'), allTime: null, resetsAt: nextMonthlyReset(),
    dataSource: 'live',
    note: 'Free REST API. Call count from PostHog.',
    dashboardUrl: 'https://www.mediawiki.org/wiki/API:REST_API',
  })

  // ── Sentry (live via stats_v2 if token configured) ───────────────────────
  const sentryToken = process.env.SENTRY_AUTH_TOKEN
  const sentryOrg = process.env.SENTRY_ORG
  if (sentryToken && sentryOrg) {
    try {
      const now = new Date()
      const monthStart = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), 1)).toISOString()
      const sentryProject = process.env.SENTRY_PROJECT ?? ''
      const projectParam = sentryProject ? `&project=${sentryProject}` : ''
      const statsRes = await fetch(
        `https://sentry.io/api/0/organizations/${sentryOrg}/stats_v2/?field=sum(quantity)&category=errors&outcome=accepted&start=${monthStart}&end=${now.toISOString()}&interval=1d${projectParam}`,
        { headers: { Authorization: `Bearer ${sentryToken}` }, next: { revalidate: 300 } }
      )
      if (!statsRes.ok) throw new Error(`HTTP ${statsRes.status}`)
      const stats = await statsRes.json()
      const errorCount: number | null = stats.groups?.[0]?.totals?.['sum(quantity)'] ?? null
      quotas.push({
        key: 'sentry', name: 'Sentry',
        limit: 5_000, limitUnit: 'errors', period: 'month',
        used: errorCount != null ? Math.round(errorCount) : null,
        allTime: null, resetsAt: nextMonthlyReset(),
        dataSource: 'live',
        note: 'Free plan — no charge below 5K errors/month.',
        dashboardUrl: 'https://sentry.io/settings/billing/overview/',
      })
    } catch (e) {
      quotas.push({
        key: 'sentry', name: 'Sentry',
        limit: 5_000, limitUnit: 'errors', period: 'month',
        used: null, allTime: null, resetsAt: nextMonthlyReset(),
        dataSource: 'static', note: `Stats API error: ${String(e)}`,
        dashboardUrl: 'https://sentry.io/settings/billing/overview/',
      })
    }
  } else {
    quotas.push({
      key: 'sentry', name: 'Sentry',
      limit: 5_000, limitUnit: 'errors', period: 'month',
      used: null, allTime: null, resetsAt: nextMonthlyReset(),
      dataSource: 'static',
      note: 'Add SENTRY_AUTH_TOKEN + SENTRY_ORG to Vercel for live counts.',
      dashboardUrl: 'https://sentry.io/settings/billing/overview/',
    })
  }

  // ── Supabase Edge Functions ───────────────────────────────────────────────
  // Invocations are self-counted via Deno KV on every request to the edge function.
  const edgeInvocations = kvCounts['supabase_edge'] ?? null
  quotas.push({
    key: 'supabase', name: 'Supabase Edge Fns',
    limit: 500_000, limitUnit: 'calls', period: 'month',
    used: edgeInvocations, allTime: null, resetsAt: nextMonthlyReset(),
    dataSource: edgeInvocations != null ? 'live' : 'static',
    note: edgeInvocations != null ? 'Self-measured via Deno KV (30d). Resets 1st of month.' : 'Measured once edge function is deployed.',
    dashboardUrl: 'https://supabase.com/dashboard/project/mtttuyvpjyugudkevchj/functions',
  })

  return NextResponse.json({ quotas, updatedAt: new Date().toISOString() })
}
