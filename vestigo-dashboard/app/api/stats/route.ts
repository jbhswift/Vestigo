import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'

const POSTHOG_HOST = process.env.POSTHOG_HOST ?? 'https://us.posthog.com'
const PROJECT_ID = process.env.POSTHOG_PROJECT_ID!
const PERSONAL_KEY = process.env.POSTHOG_PERSONAL_API_KEY!

// Map raw event names to human-readable labels
const FEATURE_LABELS: Record<string, string> = {
  tab_viewed: 'Tab Views',
  pick_for_me_started: 'Pick For Me (started)',
  pick_for_me_completed: 'Pick For Me (completed)',
  describe_it_used: 'Describe It',
  cinema_search_used: 'Cinema Search',
  search_performed: 'Search',
  item_detail_viewed: 'Detail Views',
  item_added: 'Items Added',
  item_rated: 'Ratings Given',
  friend_added: 'Friends Added',
  trailer_opened: 'Trailers Opened',
  streaming_checked: 'Streaming Checked',
  external_rating_fetched: 'Ratings Fetched (OMDb)',
}

async function hogql(query: string): Promise<unknown[][]> {
  const res = await fetch(`${POSTHOG_HOST}/api/projects/${PROJECT_ID}/query/`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${PERSONAL_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ query: { kind: 'HogQLQuery', query } }),
    next: { revalidate: 300 }, // 5-minute cache
  })
  if (!res.ok) throw new Error(`PostHog ${res.status}: ${await res.text()}`)
  const json = await res.json()
  return json.results as unknown[][]
}

export async function GET(request: NextRequest) {
  if (!PROJECT_ID || !PERSONAL_KEY) {
    return NextResponse.json({ error: 'PostHog credentials not configured' }, { status: 503 })
  }

  const { searchParams } = new URL(request.url)
  const range = Math.min(Math.max(parseInt(searchParams.get('range') ?? '30'), 7), 365)
  const distribution = searchParams.get('dist') ?? 'all' // 'all' | 'testflight' | 'appstore'

  const distFilter =
    distribution === 'testflight'
      ? `AND properties.distribution = 'testflight'`
      : distribution === 'appstore'
        ? `AND properties.distribution = 'appstore'`
        : ''

  try {
    const [usersRows, sessionsRows, featureRows, summaryRows, omdbRows] = await Promise.all([
      // Unique users per day
      hogql(`
        SELECT toDate(timestamp) AS day, uniq(person_id) AS users
        FROM events
        WHERE timestamp >= now() - INTERVAL ${range} DAY ${distFilter}
        GROUP BY day ORDER BY day ASC
      `),

      // Sessions per day (using $session_id from events)
      hogql(`
        SELECT toDate(timestamp) AS day, uniq($session_id) AS sessions
        FROM events
        WHERE timestamp >= now() - INTERVAL ${range} DAY
          AND $session_id IS NOT NULL AND $session_id != '' ${distFilter}
        GROUP BY day ORDER BY day ASC
      `),

      // Feature event breakdown (always last 30 days for the feature chart)
      hogql(`
        SELECT event, count() AS total
        FROM events
        WHERE event IN (
          'tab_viewed','pick_for_me_started','pick_for_me_completed',
          'describe_it_used','cinema_search_used','search_performed',
          'item_detail_viewed','item_added','item_rated','friend_added',
          'trailer_opened','streaming_checked','external_rating_fetched'
        )
        AND timestamp >= now() - INTERVAL 30 DAY
        GROUP BY event ORDER BY total DESC
      `),

      // Summary: total distinct users and sessions over period
      hogql(`
        SELECT
          uniq(person_id) AS total_users,
          uniq($session_id) AS total_sessions,
          count() AS total_events
        FROM events
        WHERE timestamp >= now() - INTERVAL ${range} DAY ${distFilter}
      `),

      // OMDb: count external_rating_fetched events per day for quota tracking
      hogql(`
        SELECT toDate(timestamp) AS day, count() AS calls
        FROM events
        WHERE event = 'external_rating_fetched'
          AND timestamp >= now() - INTERVAL ${range} DAY
        GROUP BY day ORDER BY day ASC
      `),
    ])

    const users = usersRows.map(([day, count]) => ({ day, count: Number(count) }))
    const sessions = sessionsRows.map(([day, count]) => ({ day, count: Number(count) }))
    const features = featureRows.map(([event, total]) => ({
      name: FEATURE_LABELS[event as string] ?? String(event),
      event: String(event),
      total: Number(total),
    }))
    const [totalUsers, totalSessions, totalEvents] = summaryRows[0] ?? [0, 0, 0]
    const omdbDaily = omdbRows.map(([day, count]) => ({ day, count: Number(count) }))

    // Groq estimates: each pick_for_me_started + describe_it_used = 1 Groq call
    const groqTotal =
      (features.find((f) => f.event === 'pick_for_me_started')?.total ?? 0) +
      (features.find((f) => f.event === 'describe_it_used')?.total ?? 0)

    // OMDb total from external_rating_fetched events
    const omdbTotal = omdbDaily.reduce((sum, d) => sum + d.count, 0)
    const omdbToday = omdbDaily.find((d) => d.day === new Date().toISOString().split('T')[0])?.count ?? 0

    // Supabase OMDb report (if migration has been applied)
    let supabaseOmdb: { report_date: string; daily_count: number; total_count: number; daily_limit: number } | null = null
    try {
      const supabaseUrl = process.env.SUPABASE_URL
      const supabaseKey = process.env.SUPABASE_SERVICE_ROLE_KEY
      if (supabaseUrl && supabaseKey) {
        const supabase = createClient(supabaseUrl, supabaseKey)
        const { data } = await supabase
          .from('omdb_usage_reports')
          .select('report_date, daily_count, total_count, daily_limit')
          .order('report_date', { ascending: false })
          .limit(1)
          .single()
        supabaseOmdb = data
      }
    } catch {
      // table may not exist yet — not a hard failure
    }

    return NextResponse.json({
      range,
      distribution,
      summary: {
        totalUsers: Number(totalUsers),
        totalSessions: Number(totalSessions),
        totalEvents: Number(totalEvents),
      },
      users,
      sessions,
      features,
      api: {
        omdb: {
          todayEstimate: omdbToday,
          periodTotal: omdbTotal,
          daily: omdbDaily,
          // More precise values from Supabase if available
          supabase: supabaseOmdb,
        },
        groq: {
          periodTotal: groqTotal,
          note: 'Each Pick For Me run + Describe It use = 1 Groq call',
        },
      },
    })
  } catch (err) {
    console.error('[stats] Error fetching data:', err)
    return NextResponse.json({ error: String(err) }, { status: 500 })
  }
}
