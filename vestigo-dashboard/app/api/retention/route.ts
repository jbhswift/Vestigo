import { NextResponse } from 'next/server'

export const dynamic = 'force-dynamic'

const POSTHOG_HOST = process.env.POSTHOG_HOST ?? 'https://us.posthog.com'
const PROJECT_ID = process.env.POSTHOG_PROJECT_ID!
const PERSONAL_KEY = process.env.POSTHOG_PERSONAL_API_KEY!

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

const FEATURE_NAMES: Record<string, string> = {
  pick_for_me_started: 'Pick For Me',
  pick_for_me_completed: 'Pick For Me (complete)',
  describe_it_used: 'Describe It',
  cinema_search_used: 'Cinema Search',
  search_performed: 'Search',
  item_detail_viewed: 'Detail View',
  item_added: 'Added to Library',
  item_rated: 'Rating Given',
  trailer_opened: 'Trailer',
  streaming_checked: 'Streaming Info',
  friend_added: 'Friend Added',
  friend_profile_viewed: 'Friend Profile',
  collection_browsed: 'Collection',
  external_rating_fetched: 'External Rating',
}

export interface RetentionStats {
  totalUsers: number | null
  retainedUsers: number | null
  retainedPct: number | null
  avgOpensAll: number | null
  avgOpensRetained: number | null
  topFeaturesAll: { event: string; name: string; count: number }[]
  topFeaturesRetained: { event: string; name: string; count: number }[]
}

export async function GET() {
  const featureList = Object.keys(FEATURE_NAMES).map(e => `'${e}'`).join(', ')

  let stats: RetentionStats = {
    totalUsers: null,
    retainedUsers: null,
    retainedPct: null,
    avgOpensAll: null,
    avgOpensRetained: null,
    topFeaturesAll: [],
    topFeaturesRetained: [],
  }

  const [sessionStats, allFeatures, retainedFeatures] = await Promise.allSettled([
    // Multi-session user breakdown
    hogql(`
      SELECT
        count(DISTINCT distinct_id) AS total_users,
        countIf(session_count >= 2) AS retained_users,
        round(avg(session_count), 1) AS avg_opens_all,
        round(avgIf(session_count, session_count >= 2), 1) AS avg_opens_retained
      FROM (
        SELECT
          distinct_id,
          count(DISTINCT $session_id) AS session_count
        FROM events
        WHERE timestamp >= now() - INTERVAL 30 DAY
          AND $session_id IS NOT NULL
          AND $session_id != ''
        GROUP BY distinct_id
      )
    `),

    // Feature usage — all users
    hogql(`
      SELECT event, count() AS total
      FROM events
      WHERE timestamp >= now() - INTERVAL 30 DAY
        AND event IN (${featureList})
      GROUP BY event
      ORDER BY total DESC
    `),

    // Feature usage — returned users only (2+ sessions)
    hogql(`
      SELECT event, count() AS total
      FROM events
      WHERE timestamp >= now() - INTERVAL 30 DAY
        AND event IN (${featureList})
        AND distinct_id IN (
          SELECT distinct_id
          FROM (
            SELECT
              distinct_id,
              count(DISTINCT $session_id) AS sessions
            FROM events
            WHERE timestamp >= now() - INTERVAL 30 DAY
              AND $session_id IS NOT NULL
              AND $session_id != ''
            GROUP BY distinct_id
          )
          WHERE sessions >= 2
        )
      GROUP BY event
      ORDER BY total DESC
    `),
  ])

  if (sessionStats.status === 'fulfilled' && sessionStats.value[0]) {
    const [total, retained, avgAll, avgRet] = sessionStats.value[0]
    stats.totalUsers = Number(total)
    stats.retainedUsers = Number(retained)
    stats.retainedPct = stats.totalUsers > 0
      ? Math.round((stats.retainedUsers / stats.totalUsers) * 100)
      : 0
    stats.avgOpensAll = Number(avgAll) || null
    stats.avgOpensRetained = Number(avgRet) || null
  }

  if (allFeatures.status === 'fulfilled') {
    stats.topFeaturesAll = allFeatures.value.map(([event, count]) => ({
      event: String(event),
      name: FEATURE_NAMES[String(event)] ?? String(event),
      count: Number(count),
    }))
  }

  if (retainedFeatures.status === 'fulfilled') {
    stats.topFeaturesRetained = retainedFeatures.value.map(([event, count]) => ({
      event: String(event),
      name: FEATURE_NAMES[String(event)] ?? String(event),
      count: Number(count),
    }))
  }

  return NextResponse.json({ stats, updatedAt: new Date().toISOString() })
}
