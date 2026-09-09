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
type RecentUser = { distinct_id: string; first_seen: string; distribution: string | null }
type RecentActivity = { event: string; rawEvent: string; timestamp: string; distinct_id: string; distribution: string | null }
type OmdbSupabase = { report_date: string; daily_count: number; total_count: number; daily_limit: number } | null

interface RetentionStats {
  totalUsers: number | null
  retainedUsers: number | null
  retainedPct: number | null
  avgOpensAll: number | null
  avgOpensRetained: number | null
  topFeaturesAll: { event: string; name: string; count: number }[]
  topFeaturesRetained: { event: string; name: string; count: number }[]
}

interface ASCRetentionData {
  sessionsPerActiveDevice: number | null
  activeDevices30d: number | null
  activeDevices7d: number | null
  activeDevices1d: number | null
  reportDate: string | null
  error?: string
}

interface QuotaItem {
  key: string
  name: string
  limit: number | null
  limitUnit: 'calls' | 'USD' | 'events' | 'errors'
  period: 'day' | 'month' | 'second'
  used: number | null
  allTime: number | null
  resetsAt: string | null
  dataSource: 'live' | 'static'
  unconfigured?: boolean
  note?: string
  dashboardUrl: string
}

interface AppleStats {
  totalTesters: number | null
  emailTesters: number | null
  publicLinkTesters: number | null
  totalBuilds: number | null
  externalGroupName: string | null
  publicLink: string | null
  publicLinkEnabled: boolean | null
  debugError?: string
}

interface StatsResponse {
  range: number
  distribution: string
  apple: AppleStats | null
  summary: { totalUsers: number; totalSessions: number; totalEvents: number }
  users: DayPoint[]
  sessions: DayPoint[]
  features: FeaturePoint[]
  recentUsers: RecentUser[]
  recentActivity: RecentActivity[]
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

function fmtUsed(n: number, unit: QuotaItem['limitUnit']) {
  if (unit === 'USD') return `$${n.toFixed(4)}`
  return n.toLocaleString()
}

function fmtLimit(n: number, unit: QuotaItem['limitUnit']) {
  if (unit === 'USD') return `$${n.toFixed(2)}`
  return fmt(n)
}

function countdown(iso: string): string {
  const ms = new Date(iso).getTime() - Date.now()
  if (ms <= 0) return 'now'
  const s = Math.floor(ms / 1000)
  const d = Math.floor(s / 86400)
  const h = Math.floor((s % 86400) / 3600)
  const m = Math.floor((s % 3600) / 60)
  if (d > 0) return h > 0 ? `${d}d ${h}h` : `${d}d`
  if (h > 0) return m > 0 ? `${h}h ${m}m` : `${h}h`
  return `${m}m`
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
  const COLORS = ['#6366f1', '#8b5cf6', '#a78bfa', '#c4b5fd', '#ddd6fe', '#ede9fe', '#e0e7ff', '#c7d2fe', '#818cf8', '#4f46e5', '#4338ca', '#3730a3']

  if (!data.length) return (
    <div className="card h-48 flex items-center justify-center text-zinc-500 text-sm">No events yet</div>
  )

  return (
    <div className="card">
      <p className="text-sm font-medium text-zinc-300 mb-4">Feature Usage <span className="text-zinc-500 font-normal">(last 30 days)</span></p>
      <ResponsiveContainer width="100%" height={Math.max(220, data.length * 32)}>
        <BarChart data={data} layout="vertical" margin={{ top: 0, right: 60, left: 4, bottom: 0 }}>
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

function RetentionFeatureChart({ data, label }: { data: { name: string; count: number }[]; label: string }) {
  const COLORS = ['#6366f1', '#8b5cf6', '#a78bfa', '#c4b5fd', '#ddd6fe', '#ede9fe', '#e0e7ff', '#c7d2fe', '#818cf8', '#4f46e5']
  if (!data.length) return (
    <div className="h-48 flex items-center justify-center text-zinc-500 text-sm">No data yet</div>
  )
  return (
    <div>
      <p className="text-sm font-medium text-zinc-400 mb-3">{label}</p>
      <ResponsiveContainer width="100%" height={Math.max(180, data.length * 30)}>
        <BarChart data={data} layout="vertical" margin={{ top: 0, right: 48, left: 4, bottom: 0 }}>
          <CartesianGrid horizontal={false} strokeDasharray="3 3" stroke="#27272a" />
          <XAxis type="number" tick={{ fontSize: 10, fill: '#71717a' }} axisLine={false} tickLine={false} />
          <YAxis
            type="category"
            dataKey="name"
            tick={{ fontSize: 11, fill: '#a1a1aa' }}
            axisLine={false}
            tickLine={false}
            width={125}
          />
          <Tooltip
            contentStyle={{ background: '#27272a', border: '1px solid #3f3f46', borderRadius: 8, color: '#fafafa' }}
            formatter={(v: number) => [v.toLocaleString(), 'events']}
            cursor={{ fill: '#27272a' }}
          />
          <Bar dataKey="count" radius={[0, 4, 4, 0]} maxBarSize={18} label={{ position: 'right', fill: '#71717a', fontSize: 11 }}>
            {data.map((_, i) => <Cell key={i} fill={COLORS[i % COLORS.length]} />)}
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
  children,
  link,
  linkLabel,
}: {
  title: string
  children: React.ReactNode
  link?: string
  linkLabel?: string
}) {
  return (
    <div className="card flex flex-col gap-2">
      <div className="flex items-center justify-between">
        <span className="text-sm font-semibold text-zinc-200">{title}</span>
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

function StatRow({ label, value, note }: { label: string; value?: string | number; note?: string }) {
  return (
    <div className="flex justify-between text-sm">
      <span className="text-zinc-400">{label}</span>
      <span className={note ? 'text-zinc-500 text-xs self-center' : 'text-zinc-200'}>
        {note ?? (typeof value === 'number' ? value.toLocaleString() : value ?? '—')}
      </span>
    </div>
  )
}

function ExpandableList({ title, totalCount, children }: { title: string; totalCount: number; children: React.ReactNode }) {
  const [expanded, setExpanded] = useState(false)
  return (
    <div className="card">
      <button onClick={() => setExpanded(!expanded)} className="w-full flex items-center justify-between">
        <span className="text-sm font-medium text-zinc-300">{title}</span>
        <div className="flex items-center gap-2">
          <span className="text-xs text-zinc-500">{totalCount} {totalCount === 1 ? 'item' : 'items'}</span>
          <svg className={`w-4 h-4 text-zinc-500 transition-transform ${expanded ? 'rotate-180' : ''}`} fill="none" stroke="currentColor" strokeWidth="2" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
          </svg>
        </div>
      </button>
      {expanded && (
        <div className="mt-3 border-t border-zinc-800 pt-3 max-h-96 overflow-y-auto">
          {children}
        </div>
      )}
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
  { label: 'Dev', value: 'development' },
]

export default function Dashboard() {
  const [range, setRange] = useState(30)
  const [dist, setDist] = useState('all')
  const [data, setData] = useState<StatsResponse | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null)
  const [quotas, setQuotas] = useState<QuotaItem[]>([])
  const [retention, setRetention] = useState<RetentionStats | null>(null)
  const [ascRetention, setAscRetention] = useState<ASCRetentionData | null>(null)
  const [, setNow] = useState(Date.now())

  const load = useCallback(async () => {
    setLoading(true)
    setError(null)
    try {
      const [statsRes, quotasRes, retentionRes, ascRes] = await Promise.all([
        fetch(`/api/stats?range=${range}&dist=${dist}`),
        fetch('/api/quotas'),
        fetch(`/api/retention?range=${range}&dist=${dist}`),
        fetch('/api/asc-retention'),
      ])
      if (!statsRes.ok) throw new Error(await statsRes.text())
      setData(await statsRes.json())
      if (quotasRes.ok) {
        const q = await quotasRes.json()
        setQuotas(q.quotas ?? [])
      }
      if (retentionRes.ok) {
        const r = await retentionRes.json()
        setRetention(r.stats ?? null)
      }
      if (ascRes.ok) {
        const a = await ascRes.json()
        if (a.data) {
          setAscRetention(a.data)
        } else if (a.error) {
          setAscRetention({ sessionsPerActiveDevice: null, activeDevices30d: null, activeDevices7d: null, activeDevices1d: null, reportDate: null, error: a.error })
        }
      }
      setLastUpdated(new Date())
    } catch (e) {
      setError(String(e))
    } finally {
      setLoading(false)
    }
  }, [range, dist])

  useEffect(() => { load() }, [load])

  // Re-render countdowns every 30s
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 30_000)
    return () => clearInterval(id)
  }, [])

  const features = data?.features ?? []
  const omdb = data?.api.omdb
  const omdbSource = omdb?.supabase
  const omdbDailyUsed = omdbSource?.daily_count ?? omdb?.todayEstimate ?? 0
  const omdbDailyLimit = omdbSource?.daily_limit ?? 1000
  const omdbTotal = omdbSource?.total_count ?? omdb?.periodTotal ?? 0
  const apple = data?.apple

  const eventCount = (event: string) => features.find(f => f.event === event)?.total ?? 0

  return (
    <main className="max-w-6xl mx-auto px-4 py-8 space-y-8">
      {/* Header */}
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between sm:gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Vestigo Dashboard</h1>
          {lastUpdated && (
            <p className="text-xs text-zinc-500 mt-0.5">
              Updated {lastUpdated.toLocaleTimeString()}
              {loading && ' · Refreshing...'}
            </p>
          )}
        </div>
        <div className="flex flex-wrap items-center gap-2 sm:gap-3">
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
            Refresh
          </button>
        </div>
      </div>

      {error && (
        <div className="card border-red-800 bg-red-950 text-red-300 text-sm">
          Error: {error}
          <br />
          <span className="text-xs text-red-400">Check that POSTHOG_PERSONAL_API_KEY and POSTHOG_PROJECT_ID (numeric team ID) are set in Vercel environment variables.</span>
        </div>
      )}

      {/* TestFlight section */}
      {apple?.debugError && (
        <div className="card border-red-800 bg-red-950 text-red-300 text-sm">
          Apple API error: {apple.debugError}
        </div>
      )}
      {apple && (
        <div>
          <div className="flex items-center justify-between mb-3">
            <h2 className="text-base font-semibold text-zinc-300">
              TestFlight
              {apple.externalGroupName && <span className="text-zinc-500 font-normal text-sm ml-2">— {apple.externalGroupName}</span>}
            </h2>
            <a
              href="https://appstoreconnect.apple.com"
              target="_blank"
              rel="noopener noreferrer"
              className="text-xs text-indigo-400 hover:text-indigo-300"
            >
              App Store Connect →
            </a>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <SummaryCard
              label="Active Testers"
              value={loading ? '—' : apple.totalTesters != null ? fmt(apple.totalTesters) : '—'}
              sub={apple.externalGroupName ?? 'external group'}
            />
            <SummaryCard
              label="Builds Submitted"
              value={loading ? '—' : apple.totalBuilds != null ? fmt(apple.totalBuilds) : '—'}
              sub="all builds"
            />
            <div className="card flex flex-col gap-2">
              <p className="text-xs text-zinc-400 uppercase tracking-wider">Invite Breakdown</p>
              <div className="space-y-1.5 mt-1">
                <StatRow label="Via Email" value={loading ? '—' : apple.emailTesters != null ? apple.emailTesters : '—'} />
                <StatRow label="Via Public Link" value={loading ? '—' : apple.publicLinkTesters != null ? apple.publicLinkTesters : '—'} />
              </div>
            </div>
          </div>
          {(apple.publicLink || apple.publicLinkEnabled != null) && (
            <div className="card mt-4 flex items-center justify-between">
              <div>
                <p className="text-xs text-zinc-400 uppercase tracking-wider">TestFlight Public Link</p>
                <p className="text-sm text-zinc-300 mt-0.5">
                  {apple.publicLinkEnabled ? 'Enabled' : 'Disabled'}
                </p>
              </div>
              {apple.publicLink && (
                <a
                  href={apple.publicLink}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="text-xs text-indigo-400 hover:text-indigo-300 font-mono truncate max-w-xs"
                >
                  {apple.publicLink}
                </a>
              )}
            </div>
          )}
        </div>
      )}

      {/* PostHog summary cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <SummaryCard
          label={`Active Users (${range}d)`}
          value={loading ? '—' : fmt(data?.summary.totalUsers ?? 0)}
          sub={dist !== 'all' ? dist : 'from PostHog'}
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

      {/* Recent Users */}
      {!loading && (data?.recentUsers?.length ?? 0) > 0 && (
        <ExpandableList title="Most Recent Users" totalCount={data!.recentUsers.length}>
          {data!.recentUsers.map((user, i) => (
            <div key={i} className="flex items-center justify-between py-1.5 text-sm border-b border-zinc-800/50 last:border-0">
              <span className="font-mono text-xs text-zinc-400 truncate max-w-[180px] sm:max-w-xs">{user.distinct_id}</span>
              <div className="flex items-center gap-2 shrink-0 ml-2">
                {user.distribution && (
                  <span className="text-[10px] px-1.5 py-0.5 rounded bg-zinc-800 text-zinc-400">{user.distribution}</span>
                )}
                <span className="text-xs text-zinc-500">
                  {new Date(user.first_seen).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })}
                </span>
              </div>
            </div>
          ))}
        </ExpandableList>
      )}

      {/* Returning Users */}
      <div>
        <h2 className="text-base font-semibold text-zinc-300 mb-3">Returning Users <span className="text-zinc-500 font-normal text-sm">— last {range} days</span></h2>

        {/* PostHog-based retention */}
        <p className="text-xs text-zinc-500 uppercase tracking-wider mb-2">From PostHog</p>
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-4">
          <SummaryCard
            label="Returned (2+ opens)"
            value={loading || !retention ? '—' : retention.retainedUsers != null ? fmt(retention.retainedUsers) : '—'}
            sub={retention?.retainedPct != null ? `${retention.retainedPct}% of all users` : 'of all users'}
          />
          <SummaryCard
            label="Avg Opens (all users)"
            value={loading || !retention ? '—' : retention.avgOpensAll != null ? String(retention.avgOpensAll) : '—'}
            sub="app opens per person"
          />
          <SummaryCard
            label="Avg Opens (returners)"
            value={loading || !retention ? '—' : retention.avgOpensRetained != null ? String(retention.avgOpensRetained) : '—'}
            sub="among people who came back"
          />
        </div>
        {retention && (retention.topFeaturesRetained.length > 0 || retention.topFeaturesAll.length > 0) && (
          <div className="card grid grid-cols-1 sm:grid-cols-2 gap-6 mb-4">
            <RetentionFeatureChart
              data={retention.topFeaturesRetained}
              label="Features used by returning users"
            />
            <RetentionFeatureChart
              data={retention.topFeaturesAll}
              label="Features used by all users"
            />
          </div>
        )}
        {retention && retention.topFeaturesRetained.length === 0 && retention.topFeaturesAll.length === 0 && (
          <div className="card h-32 flex items-center justify-center text-zinc-500 text-sm mb-4">
            No feature events yet — ship a build with analytics to see data
          </div>
        )}
      </div>

      {/* Timeline charts */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
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
      <FeatureChart data={features} />

      {/* Recent Activity */}
      {!loading && (data?.recentActivity?.length ?? 0) > 0 && (
        <ExpandableList title="Most Recent Actions" totalCount={data!.recentActivity.length}>
          {data!.recentActivity.map((action, i) => (
            <div key={i} className="flex items-center justify-between py-1.5 text-sm border-b border-zinc-800/50 last:border-0">
              <div className="flex items-center gap-2 min-w-0">
                <span className="text-zinc-200 text-xs shrink-0">{action.event}</span>
                <span className="font-mono text-[10px] text-zinc-600 truncate">{action.distinct_id}</span>
              </div>
              <div className="flex items-center gap-2 shrink-0 ml-2">
                {action.distribution && (
                  <span className="text-[10px] px-1.5 py-0.5 rounded bg-zinc-800 text-zinc-400">{action.distribution}</span>
                )}
                <span className="text-xs text-zinc-500">
                  {new Date(action.timestamp).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })}
                </span>
              </div>
            </div>
          ))}
        </ExpandableList>
      )}

      {/* App Store Connect engagement */}
      <div>
        <h2 className="text-base font-semibold text-zinc-300 mb-3">
          App Store Connect Engagement
          {ascRetention?.reportDate && <span className="text-zinc-500 font-normal text-sm ml-2">— data through {ascRetention.reportDate}</span>}
        </h2>
        {ascRetention?.error && !ascRetention.activeDevices30d ? (
          <div className="card text-sm text-zinc-500">{ascRetention.error}</div>
        ) : (
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <SummaryCard
              label="Sessions / Active Device"
              value={loading || !ascRetention ? '—' : ascRetention.sessionsPerActiveDevice != null ? String(ascRetention.sessionsPerActiveDevice) : '—'}
              sub="avg across 30d active devices"
            />
            <SummaryCard
              label="Active Devices (30d)"
              value={loading || !ascRetention ? '—' : ascRetention.activeDevices30d != null ? fmt(ascRetention.activeDevices30d) : '—'}
              sub="unique devices that opened app"
            />
            <SummaryCard
              label="Active Devices (yesterday)"
              value={loading || !ascRetention ? '—' : ascRetention.activeDevices1d != null ? fmt(ascRetention.activeDevices1d) : '—'}
              sub="most recent day in report"
            />
          </div>
        )}
      </div>

      {/* API Quotas */}
      {quotas.length > 0 && (
        <div>
          <h2 className="text-base font-semibold text-zinc-300 mb-3">API Quotas</h2>
          <div className="card overflow-hidden p-0 overflow-x-auto">
            <table className="w-full text-sm min-w-[600px]">
              <thead>
                <tr className="border-b border-zinc-800">
                  <th className="text-left text-xs text-zinc-500 font-medium uppercase tracking-wider px-4 py-2.5">API</th>
                  <th className="text-right text-xs text-zinc-500 font-medium uppercase tracking-wider px-4 py-2.5">Limit</th>
                  <th className="text-right text-xs text-zinc-500 font-medium uppercase tracking-wider px-4 py-2.5">Per</th>
                  <th className="text-left text-xs text-zinc-500 font-medium uppercase tracking-wider px-4 py-2.5 w-48">Used this period</th>
                  <th className="text-right text-xs text-zinc-500 font-medium uppercase tracking-wider px-4 py-2.5">All-time</th>
                  <th className="text-right text-xs text-zinc-500 font-medium uppercase tracking-wider px-4 py-2.5">Resets in</th>
                  <th className="text-right text-xs text-zinc-500 font-medium uppercase tracking-wider px-4 py-2.5"></th>
                </tr>
              </thead>
              <tbody>
                {quotas.map((q, i) => {
                  const pct = q.used != null && q.limit != null ? Math.min(100, (q.used / q.limit) * 100) : null
                  const barColor = pct == null ? '#3f3f46' : pct >= 90 ? '#ef4444' : pct >= 70 ? '#f59e0b' : '#22c55e'
                  const isStrained = pct != null && pct >= 70
                  return (
                    <tr key={q.key} className={`border-b border-zinc-800/50 last:border-0 ${isStrained ? 'bg-amber-950/10' : ''}`}>
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-2">
                          <span className={`font-medium ${isStrained ? 'text-amber-300' : 'text-zinc-200'}`}>{q.name}</span>
                          {q.dataSource === 'live' && (
                            <span className="text-[10px] px-1.5 py-0.5 rounded bg-emerald-900/50 text-emerald-400 font-medium">live</span>
                          )}
                          {q.unconfigured && (
                            <span className="text-[10px] px-1.5 py-0.5 rounded bg-zinc-800 text-zinc-500 font-medium">no key</span>
                          )}
                        </div>
                        {q.note && <p className="text-[11px] text-zinc-500 mt-0.5">{q.note}</p>}
                      </td>
                      <td className="px-4 py-3 text-right tabular-nums text-zinc-200">
                        {q.limit != null ? fmtLimit(q.limit, q.limitUnit) : '—'}
                      </td>
                      <td className="px-4 py-3 text-right text-zinc-400">{q.period}</td>
                      <td className="px-4 py-3">
                        {q.used != null ? (
                          <div className="flex flex-col gap-1">
                            <div className="flex items-center justify-between">
                              <span className="tabular-nums text-zinc-200">{fmtUsed(q.used, q.limitUnit)}</span>
                              {pct != null && (
                                <span className="text-[11px] tabular-nums" style={{ color: barColor }}>
                                  {pct < 1 ? '<1%' : `${Math.round(pct)}%`}
                                </span>
                              )}
                            </div>
                            {pct != null && (
                              <div className="h-1 bg-zinc-800 rounded-full overflow-hidden w-36">
                                <div className="h-full rounded-full" style={{ width: `${pct}%`, background: barColor }} />
                              </div>
                            )}
                          </div>
                        ) : (
                          <span className="text-zinc-600">—</span>
                        )}
                      </td>
                      <td className="px-4 py-3 text-right tabular-nums text-zinc-400">
                        {q.allTime != null ? q.allTime.toLocaleString() : '—'}
                      </td>
                      <td className="px-4 py-3 text-right tabular-nums text-zinc-400">
                        {q.resetsAt ? countdown(q.resetsAt) : '—'}
                      </td>
                      <td className="px-4 py-3 text-right">
                        <a
                          href={q.dashboardUrl}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="text-xs text-indigo-400 hover:text-indigo-300"
                        >
                          →
                        </a>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* External links */}
      <div className="card">
        <p className="text-xs font-medium text-zinc-400 uppercase tracking-wider mb-3">External Dashboards</p>
        <div className="flex flex-wrap gap-2 sm:gap-3">
          {[
            { label: 'PostHog', href: 'https://us.posthog.com' },
            { label: 'Sentry', href: 'https://sentry.io' },
            { label: 'Supabase', href: 'https://supabase.com/dashboard/project/mtttuyvpjyugudkevchj' },
            { label: 'OpenRouter', href: 'https://openrouter.ai/activity' },
            { label: 'Watchmode', href: 'https://api.watchmode.com/' },
            { label: 'TVDB', href: 'https://thetvdb.com/dashboard' },
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
              {link.label} →
            </a>
          ))}
        </div>
      </div>
    </main>
  )
}
