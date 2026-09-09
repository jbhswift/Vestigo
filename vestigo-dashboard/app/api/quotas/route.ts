import { NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

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

export async function GET() {
  const quotas: QuotaItem[] = []

  // Fetch PostHog api_call counts for this month (best-effort — won't exist until app builds are distributed)
  let phCounts: Record<string, number> = {}
  try {
    phCounts = await apiCallCountsByService()
  } catch { /* non-fatal */ }

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
  const watchmodeKey = process.env.WATCHMODE_API_KEY
  if (watchmodeKey) {
    try {
      const wmRes = await fetch(`https://api.watchmode.com/v1/status/?apiKey=${watchmodeKey}`, {
        next: { revalidate: 300 },
      })
      if (!wmRes.ok) throw new Error(`HTTP ${wmRes.status}`)
      const wm = await wmRes.json()
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
        used: phCounts['watchmode'] ?? null, allTime: null, resetsAt: nextMonthlyReset(),
        dataSource: 'live',
        note: `Status API error: ${String(e)} — count from PostHog.`,
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
        used: phCounts['brandfetch'] ?? null, allTime: null, resetsAt: endOfMonthReset(),
        dataSource: 'live',
        note: `API error: ${String(e)} — count from PostHog.`,
        dashboardUrl: 'https://brandfetch.com/dashboard',
      })
    }
  } else {
    quotas.push({
      key: 'brandfetch', name: 'Brandfetch',
      limit: 1_000_000, limitUnit: 'calls', period: 'month',
      used: phCounts['brandfetch'] ?? null, allTime: null, resetsAt: endOfMonthReset(),
      dataSource: phCounts['brandfetch'] != null ? 'live' : 'static',
      unconfigured: true,
      note: 'Add BRANDFETCH_CLIENT_ID to Vercel env vars.',
      dashboardUrl: 'https://brandfetch.com/dashboard',
    })
  }

  // ── OpenRouter (live if key set) ─────────────────────────────────────────
  const openrouterKey = process.env.OPENROUTER_API_KEY
  if (openrouterKey) {
    try {
      const res = await fetch('https://openrouter.ai/api/v1/auth/key', {
        headers: { Authorization: `Bearer ${openrouterKey}` },
        next: { revalidate: 60 },
      })
      if (!res.ok) throw new Error(String(res.status))
      const d = await res.json()
      const spend = d.data?.usage != null ? Math.round(d.data.usage * 10000) / 10000 : null
      quotas.push({
        key: 'openrouter', name: 'OpenRouter (AI)',
        limit: null,
        limitUnit: 'calls', period: 'month',
        used: phCounts['openrouter'] ?? null,
        allTime: null,
        resetsAt: nextMonthlyReset(),
        dataSource: 'live',
        note: spend != null && spend > 0 ? `Spend: $${spend}` : 'Free models only — call count from PostHog.',
        dashboardUrl: 'https://openrouter.ai/settings/keys',
      })
    } catch (e) {
      quotas.push({
        key: 'openrouter', name: 'OpenRouter (AI)',
        limit: null, limitUnit: 'USD', period: 'month',
        used: null, allTime: null, resetsAt: nextMonthlyReset(),
        dataSource: 'static', note: `Key API error: ${String(e)}`,
        dashboardUrl: 'https://openrouter.ai/settings/keys',
      })
    }
  } else {
    quotas.push({
      key: 'openrouter', name: 'OpenRouter (AI)',
      limit: null, limitUnit: 'USD', period: 'month',
      used: phCounts['openrouter'] ?? null, allTime: null, resetsAt: nextMonthlyReset(),
      dataSource: 'live',
      note: 'Pick For Me AI ranking — via Supabase backend. Call count from PostHog.',
      dashboardUrl: 'https://openrouter.ai/settings/keys',
    })
  }

  // ── OpenRouter backup (live if key set) ──────────────────────────────────
  const openrouterBackupKey = process.env.OPENROUTER_BACKUP_KEY
  if (openrouterBackupKey) {
    try {
      const res = await fetch('https://openrouter.ai/api/v1/auth/key', {
        headers: { Authorization: `Bearer ${openrouterBackupKey}` },
        next: { revalidate: 60 },
      })
      if (!res.ok) throw new Error(String(res.status))
      const d = await res.json()
      const backupSpend = d.data?.usage != null ? Math.round(d.data.usage * 10000) / 10000 : null
      quotas.push({
        key: 'openrouter_backup', name: 'OpenRouter (backup key)',
        limit: null,
        limitUnit: 'calls', period: 'month',
        used: null,
        allTime: null,
        resetsAt: nextMonthlyReset(),
        dataSource: 'live',
        note: backupSpend != null && backupSpend > 0 ? `Spend: $${backupSpend}` : 'Free models only — fallback key.',
        dashboardUrl: 'https://openrouter.ai/settings/keys',
      })
    } catch (e) {
      quotas.push({
        key: 'openrouter_backup', name: 'OpenRouter (backup key)',
        limit: null, limitUnit: 'USD', period: 'month',
        used: null, allTime: null, resetsAt: nextMonthlyReset(),
        dataSource: 'static', note: `Key API error: ${String(e)}`,
        dashboardUrl: 'https://openrouter.ai/settings/keys',
      })
    }
  }

  // ── Groq ─────────────────────────────────────────────────────────────────
  quotas.push({
    key: 'groq', name: 'Groq',
    limit: null, limitUnit: 'calls', period: 'month',
    used: phCounts['groq'] ?? null, allTime: null, resetsAt: nextMonthlyReset(),
    dataSource: process.env.GROQ_API_KEY ? 'live' : 'static',
    note: process.env.GROQ_API_KEY
      ? 'AI inference (backend). No usage API — count from PostHog.'
      : 'Key not configured in Vercel.',
    dashboardUrl: 'https://console.groq.com/usage',
  })

  // ── Cerebras ──────────────────────────────────────────────────────────────
  quotas.push({
    key: 'cerebras', name: 'Cerebras',
    limit: null, limitUnit: 'calls', period: 'month',
    used: phCounts['cerebras'] ?? null, allTime: null, resetsAt: nextMonthlyReset(),
    dataSource: process.env.CEREBRAS_API_KEY ? 'live' : 'static',
    note: process.env.CEREBRAS_API_KEY
      ? 'AI inference (backend). No usage API — count from PostHog.'
      : 'Key not configured in Vercel.',
    dashboardUrl: 'https://cloud.cerebras.ai/',
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
    used: phCounts['tmdb'] ?? null, allTime: null, resetsAt: nextMonthlyReset(),
    dataSource: 'live',
    note: 'No hard monthly limit. Rate-limited to ~40 req/10s. Call count from PostHog.',
    dashboardUrl: 'https://www.themoviedb.org/settings/api',
  })

  // ── TVDB ─────────────────────────────────────────────────────────────────
  quotas.push({
    key: 'tvdb', name: 'TVDB',
    limit: null, limitUnit: 'calls', period: 'month',
    used: phCounts['tvdb'] ?? null, allTime: null, resetsAt: nextMonthlyReset(),
    dataSource: 'live',
    note: 'Call count from PostHog.',
    dashboardUrl: 'https://thetvdb.com/dashboard',
  })

  // ── AMC Theatres ─────────────────────────────────────────────────────────
  quotas.push({
    key: 'amc', name: 'AMC Theatres',
    limit: null, limitUnit: 'calls', period: 'month',
    used: phCounts['amc'] ?? null, allTime: null, resetsAt: nextMonthlyReset(),
    dataSource: 'live',
    note: 'Call count from PostHog.',
    dashboardUrl: 'https://api.amctheatres.com',
  })

  // ── Wikidata ──────────────────────────────────────────────────────────────
  quotas.push({
    key: 'wikidata', name: 'Wikidata',
    limit: null, limitUnit: 'calls', period: 'month',
    used: phCounts['wikidata'] ?? null, allTime: null, resetsAt: nextMonthlyReset(),
    dataSource: 'live',
    note: 'Free SPARQL endpoint. Call count from PostHog.',
    dashboardUrl: 'https://query.wikidata.org/',
  })

  // ── YouTube (short detection) ─────────────────────────────────────────────
  quotas.push({
    key: 'youtube', name: 'YouTube',
    limit: null, limitUnit: 'calls', period: 'month',
    used: phCounts['youtube'] ?? null, allTime: null, resetsAt: nextMonthlyReset(),
    dataSource: 'live',
    note: 'Short detection only. Call count from PostHog.',
    dashboardUrl: 'https://console.cloud.google.com/',
  })

  // ── Wikipedia ─────────────────────────────────────────────────────────────
  quotas.push({
    key: 'wikipedia', name: 'Wikipedia',
    limit: null, limitUnit: 'calls', period: 'month',
    used: phCounts['wikipedia'] ?? null, allTime: null, resetsAt: nextMonthlyReset(),
    dataSource: 'live',
    note: 'Free REST API. Call count from PostHog.',
    dashboardUrl: 'https://www.mediawiki.org/wiki/API:REST_API',
  })

  // ── Sentry (no usage API) ────────────────────────────────────────────────
  quotas.push({
    key: 'sentry', name: 'Sentry',
    limit: 5000, limitUnit: 'errors', period: 'month',
    used: null, allTime: null, resetsAt: nextMonthlyReset(),
    dataSource: 'static',
    note: 'No programmatic usage API.',
    dashboardUrl: 'https://sentry.io/settings/billing/overview/',
  })

  // ── Supabase Edge Functions ───────────────────────────────────────────────
  quotas.push({
    key: 'supabase', name: 'Supabase Edge Fns',
    limit: 500_000, limitUnit: 'calls', period: 'month',
    used: null, allTime: null, resetsAt: nextMonthlyReset(),
    dataSource: 'static',
    note: 'No programmatic usage API.',
    dashboardUrl: 'https://supabase.com/dashboard/project/mtttuyvpjyugudkevchj/functions',
  })

  return NextResponse.json({ quotas, updatedAt: new Date().toISOString() })
}
