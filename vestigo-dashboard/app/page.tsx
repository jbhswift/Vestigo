'use client'

import { useEffect, useState, useCallback } from 'react'
import {
  AreaChart,
  Area,
  BarChart,
  Bar,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  Cell,
} from 'recharts'

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

type DayPoint = { day: string; count: number }
type FeaturePoint = { name: string; event: string; total: number }
type OmdbSupabase = { report_date: string; daily_count: number; total_count: number; daily_limit: number } | null

interface StatsResponse {
  range: number
  distribution: string
  summary: { totalUsers: number; totalSessions: number; totalEvents: number }
  users: DayPoint[]
  sessions: DayPoint[]
  features: FeaturePoint[]
  api: {
    omdb: { todayEstimate: number; periodTotal: number; daily: DayPoint[]; supabase: OmdbSupabase }
    groq: { periodTotal: number; note: string }
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function fmt(n: number) {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M'
  if (n >= 1_000) return (n / 1_000).toFixed(1) + 'K'
  return String(n)
}

function shortDate(iso: string) {
  const d = new Date(iso + 'T00:00:00')
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

function pct(value: number, total: number) {
  if (!total) return 0
  return Math.min(100, Math.round((value / total) * 100))
}

// ---------------------------------------------------------------------------
// Sub-components
// ---------------------------------------------------------------------------

function SummaryCard({ label, value, sub }: { label: string; value: string; sub?: string }) {
  return (
    <div className="card flex flex-col gap-1">
      <p className="text-xs text-zinc-400 uppercase tracking-wider">{label}</p>
      <p className="text-3xl font-semibold tabular-nums">{value}</p>
      {sub && <p className="text-xs text-zinc-500">{sub}</p>}
    </div>
  )
}

function TimelineChart({ data, color, label }: { data: DayPoint[]; color: string; label: string }) {
  if (!data.length) return <div className="card h-48 flex items-center justify-center text-zinc-500 text-sm">No data yet</div>
  return (
    <div className="card">
      <p className="text-sm font-medium text-zinc-300 mb-4">{label}</p>
      <ResponsiveContainer width="100%" height={180}>
        <AreaChart data={data} margin={{ top: 4, right: 4, left: -20, bottom: 0 }}>
          <defs>
            <linearGradient id={`grad-${color}`} x1="0" y1="0" x2="0" y2="1">
              <stop offset="5%" stopColor={color} stopOpacity={0.25} />
              <stop offset="95%" stopColor={color} stopOpacity={0} />
            </linearGradient>
          </defs>
          <CartesianGrid vertical={false} strokeDasharray="3 3" stroke="#27272a" />
          <XAxis
            dataKey="day"
            tickFormatter={shortDate}
            tick={{ fontSize: 10, fill: '#71717a' }}
            axisLine={false}
            tickLine={false}
            interval="preserveStartEnd"
          />
          <YAxis tick={{ fontSize: 10, fill: '#71717a' }} axisLine={false} tickLine={false} allowDecimals={false} />
          <Tooltip
            contentStyle={{ background: '#27272a', border: '1px solid #3f3f46', borderRadius: 8, color: '#fafafa' }}
            labelFormatter={shortDate}
            formatter={(v: number) => [v, label]}
          />
          <Area
            type="monotone"
            dataKey="count"
            stroke={color}
            strokeWidth={2}
            fill={`url(#grad-${color})`}
            dot={false}
            activeDot={{ r: 4, fill: color }}
          />
        </AreaChart>
      </ResponsiveContainer>
    </div>
  )
}

function FeatureChart({ data }: { data: FeaturePoint[] }) {
  const max = data[0]?.total ?? 1
  const COLORS = ['#6366f1', '#8b5cf6', '#a78bfa', '#c4b5fd', '#ddd6fe', '#ede9fe', '#e0e7ff', '#c7d2fe', '#818cf8', '#4f46e5', '#4338ca', '#3730a3']

  if (!data.length) return (
    <div className="card h-48 flex items-center justify-center text-zinc-500 text-sm">No events yet — instrument the app and use it.</div>
  )

  return (
    <div className="card">
      <p className="text-sm font-medium text-zinc-300 mb-4">Feature Usage <span className="text-zinc-500 font-normal">(last 30 days)</span></p>
      <ResponsiveContainer width="100%" height={Math.max(220, data.length * 32)}>
        <BarChart data={data} layout="vertical" margin={{ top: 0, right: 60, left: 140, bottom: 0 }}>
          <CartesianGrid horizontal={false} strokeDasharray="3 3" stroke="#27272a" />
          <XAxis type="number" tick={{ fontSize: 10, fill: '#71717a' }} axisLine={false} tickLine={false} />
          <YAxis
            type="category"
            dataKey="name"
            tick={{ fontSize: 12, fill: '#a1a1aa' }}
            axisLine={false}
            tickLine={false}
            width={135}
          />
          <Tooltip
            contentStyle={{ background: '#27272a', border: '1px solid #3f3f46', borderRadius: 8, color: '#fafafa' }}
            formatter={(v: number) => [v.toLocaleString(), 'events']}
            cursor={{ fill: '#27272a' }}
          />
          <Bar dataKey="total" radius={[0, 4, 4, 0]} maxBarSize={20} label={{ position: 'right', fill: '#71717a', fontSize: 11 }}>
            {data.map((_, i) => (
              <Cell key={i} fill={COLORS[i % COLORS.length]} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  )
}

function QuotaBar({ used, total, label }: { used: number; total: number; label: string }) {
  const p = pct(used, total)
  const color = p >= 90 ? '#ef4444' : p >= 70 ? '#f59e0b' : '#22c55e'
  return (
    <div className="mt-3">
      <div className="flex justify-between text-xs text-zinc-400 mb-1">
        <span>{label}</span>
        <span>{used.toLocaleString()} / {total.toLocaleString()}</span>
      </div>
      <div className="h-1.5 bg-zinc-800 rounded-full overflow-hidden">
        <div className="h-full rounded-full transition-all" style={{ width: `${p}%`, background: color }} />
      </div>
    </div>
  )
}

function ApiCard({
  title,
  icon,
  children,
  link,
  linkLabel,
}: {
  title: string
  icon: string
  children: React.ReactNode
  link?: string
  linkLabel?: string
}) {
  return (
    <div className="card flex flex-col gap-2">
      <div className="flex items-center justify-between">
        <span className="text-sm font-semibold text-zinc-200">{icon} {title}</span>
        {link && (
          <a href={link} target="_blank" rel="noopener noreferrer" className="text-xs text-indigo-400 hover:text-indigo-300">
            {linkLabel ?? 'Dashboard →'}
          </a>
        )}
      </div>
      {children}
    </div>
  )
}

// ---------------------------------------------------------------------------
// Main dashboard
// ---------------------------------------------------------------------------

const RANGES = [
  { label: '7D', value: 7 },
  { label: '30D', value: 30 },
  { label: '90D', value: 90 },
]

const DISTS = [
  { label: 'All', value: 'all' },
  { label: 'TestFlight', value: 'testflight' },
  { label: 'App Store', value: 'appstore' },
]

export default function Dashboard() {
  const [range, setRange] = useState(30)
  const [dist, setDist] = useState('all')
  const [data, setData] = useState<StatsResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const res = await fetch(`/api/stats?range=${range}&dist=${dist}`)
      if (!res.ok) throw new Error(await res.text())
      setData(await res.json())
      setLastUpdated(new Date())
    } catch (e) {
      setError(String(e))
    } finally {
      setLoading(false)
    }
  }, [range, dist])

  useEffect(() => { load() }, [load])

  const omdb = data?.api.omdb
  const omdbSource = omdb?.supabase // precise data from Supabase if migration applied
  const omdbDailyUsed = omdbSource?.daily_count ?? omdb?.todayEstimate ?? 0
  const omdbDailyLimit = omdbSource?.daily_limit ?? 1000
  const omdbTotal = omdbSource?.total_count ?? omdb?.periodTotal ?? 0

  return (
    <main className="max-w-6xl mx-auto px-4 py-8 space-y-8">
      {/* Header */}
      <div className="flex flex-wrap items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">🎬 Vestigo Dashboard</h1>
          {lastUpdated && (
            <p className="text-xs text-zinc-500 mt-0.5">
              Updated {lastUpdated.toLocaleTimeString()}
              {loading && ' · Refreshing…'}
            </p>
          )}
        </div>
        <div className="flex items-center gap-3">
          {/* Distribution filter */}
          <div className="flex rounded-lg overflow-hidden border border-zinc-700">
            {DISTS.map((d) => (
              <button
                key={d.value}
                onClick={() => setDist(d.value)}
                className={`px-3 py-1.5 text-xs font-medium transition-colors ${
                  dist === d.value ? 'bg-indigo-600 text-white' : 'text-zinc-400 hover:text-zinc-200'
                }`}
              >
                {d.label}
              </button>
            ))}
          </div>
          {/* Time range */}
          <div className="flex rounded-lg overflow-hidden border border-zinc-700">
            {RANGES.map((r) => (
              <button
                key={r.value}
                onClick={() => setRange(r.value)}
                className={`px-3 py-1.5 text-xs font-medium transition-colors ${
                  range === r.value ? 'bg-indigo-600 text-white' : 'text-zinc-400 hover:text-zinc-200'
                }`}
              >
                {r.label}
              </button>
            ))}
          </div>
          <button
            onClick={load}
            disabled={loading}
            className="px-3 py-1.5 text-xs font-medium rounded-lg border border-zinc-700 text-zinc-400 hover:text-zinc-200 disabled:opacity-40 transition-colors"
          >
            ↻ Refresh
          </button>
        </div>
      </div>

      {error && (
        <div className="card border-red-800 bg-red-950 text-red-300 text-sm">
          ⚠ {error}
          <br />
          <span className="text-xs text-red-400">Check that POSTHOG_PERSONAL_API_KEY and POSTHOG_PROJECT_ID are set in your .env.local</span>
        </div>
      )}

      {/* Summary cards */}
      <div className="grid grid-cols-3 gap-4">
        <SummaryCard
          label={`Unique Users (${range}d)`}
          value={loading ? '—' : fmt(data?.summary.totalUsers ?? 0)}
          sub={dist !== 'all' ? dist : undefined}
        />
        <SummaryCard
          label={`Sessions (${range}d)`}
          value={loading ? '—' : fmt(data?.summary.totalSessions ?? 0)}
        />
        <SummaryCard
          label={`Events (${range}d)`}
          value={loading ? '—' : fmt(data?.summary.totalEvents ?? 0)}
        />
      </div>

      {/* Timeline charts */}
      <div className="grid grid-cols-2 gap-4">
        <TimelineChart
          data={data?.users ?? []}
          color="#6366f1"
          label={`Unique Users per Day (${range}d${dist !== 'all' ? ` · ${dist}` : ''})`}
        />
        <TimelineChart
          data={data?.sessions ?? []}
          color="#22c55e"
          label={`Sessions per Day (${range}d)`}
        />
      </div>

      {/* Feature usage */}
      <FeatureChart data={data?.features ?? []} />

      {/* API Keys */}
      <div>
        <h2 className="text-base font-semibold text-zinc-300 mb-3">API Keys</h2>
        <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
          {/* OMDb */}
          <ApiCard title="OMDb" icon="🎭" link="https://www.omdbapi.com/" linkLabel="omdbapi.com →">
            <div className="space-y-1 text-sm">
              <div className="flex justify-between text-zinc-300">
                <span className="text-zinc-400">Today</span>
                <span className={omdbDailyUsed / omdbDailyLimit > 0.9 ? 'text-red-400 font-medium' : ''}>{omdbDailyUsed.toLocaleString()}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-zinc-400">Daily limit</span>
                <span>{omdbDailyLimit.toLocaleString()}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-zinc-400">Period total</span>
                <span>{omdbTotal.toLocaleString()}</span>
              </div>
            </div>
            <QuotaBar used={omdbDailyUsed} total={omdbDailyLimit} label="Daily quota" />
            {!omdbSource && (
              <p className="text-xs text-zinc-600 mt-2">Apply Supabase migration for precise device-reported values</p>
            )}
          </ApiCard>

          {/* Groq */}
          <ApiCard title="Groq" icon="🧠" link="https://console.groq.com" linkLabel="console.groq.com →">
            <div className="space-y-1 text-sm">
              <div className="flex justify-between">
                <span className="text-zinc-400">Calls ({range}d)</span>
                <span>{(data?.api.groq.periodTotal ?? 0).toLocaleString()}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-zinc-400">PFM runs</span>
                <span>{(data?.features.find(f => f.event === 'pick_for_me_started')?.total ?? 0).toLocaleString()}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-zinc-400">Describe It</span>
                <span>{(data?.features.find(f => f.event === 'describe_it_used')?.total ?? 0).toLocaleString()}</span>
              </div>
            </div>
            <p className="text-xs text-zinc-600 mt-2">Estimated from PostHog events. See Groq console for token usage.</p>
          </ApiCard>

          {/* TMDb */}
          <ApiCard title="TMDb" icon="🎬" link="https://www.themoviedb.org/settings/api" linkLabel="tmdb.org →">
            <div className="space-y-1 text-sm">
              <div className="flex justify-between">
                <span className="text-zinc-400">Detail views</span>
                <span>{(data?.features.find(f => f.event === 'item_detail_viewed')?.total ?? 0).toLocaleString()}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-zinc-400">Searches</span>
                <span>{(data?.features.find(f => f.event === 'search_performed')?.total ?? 0).toLocaleString()}</span>
              </div>
            </div>
            <p className="text-xs text-zinc-600 mt-2">Proxied via Supabase. See Supabase Edge Function logs for exact counts.</p>
          </ApiCard>

          {/* Supabase */}
          <ApiCard
            title="Supabase"
            icon="⚡"
            link={`https://supabase.com/dashboard/project/mtttuyvpjyugudkevchj`}
            linkLabel="supabase.com →"
          >
            <div className="space-y-1 text-sm">
              <div className="flex justify-between">
                <span className="text-zinc-400">Edge Functions</span>
                <span className="text-zinc-500 text-xs">2M / mo free</span>
              </div>
              <div className="flex justify-between">
                <span className="text-zinc-400">Postgres</span>
                <span className="text-zinc-500 text-xs">500 MB free</span>
              </div>
              <div className="flex justify-between">
                <span className="text-zinc-400">Auth</span>
                <span className="text-zinc-500 text-xs">50K MAU free</span>
              </div>
            </div>
            <p className="text-xs text-zinc-600 mt-2">See Supabase dashboard for live invocation counts and DB size.</p>
          </ApiCard>
        </div>
      </div>

      {/* External links */}
      <div className="card">
        <p className="text-xs font-medium text-zinc-400 uppercase tracking-wider mb-3">External Dashboards</p>
        <div className="flex flex-wrap gap-3">
          {[
            { label: 'PostHog', href: 'https://us.posthog.com' },
            { label: 'Sentry', href: 'https://sentry.io' },
            { label: 'Supabase', href: 'https://supabase.com/dashboard/project/mtttuyvpjyugudkevchj' },
            { label: 'Groq Console', href: 'https://console.groq.com' },
            { label: 'App Store Connect', href: 'https://appstoreconnect.apple.com' },
            { label: 'CloudKit Console', href: 'https://icloud.developer.apple.com/dashboard' },
            { label: 'TMDb API', href: 'https://www.themoviedb.org/settings/api' },
          ].map((link) => (
            <a
              key={link.label}
              href={link.href}
              target="_blank"
              rel="noopener noreferrer"
              className="px-3 py-1.5 text-xs rounded-lg border border-zinc-700 text-zinc-400 hover:text-zinc-200 hover:border-zinc-500 transition-colors"
            >
              {link.label} ↗
            </a>
          ))}
        </div>
      </div>
    </main>
  )
}
