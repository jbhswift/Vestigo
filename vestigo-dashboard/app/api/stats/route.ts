import { NextRequest, NextResponse } from 'next/server'
import { createClient } from '@supabase/supabase-js'
import { SignJWT, importPKCS8 } from 'jose'

export const dynamic = 'force-dynamic'

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
  friend_profile_viewed: 'Friend Profile Views',
  collection_browsed: 'Collections Browsed',
  trailer_opened: 'Trailers Opened',
  streaming_checked: 'Streaming Checked',
  external_rating_fetched: 'Ratings Fetched (OMDb)',
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

function normalizePem(raw: string): string {
  const pem = raw.replace(/\\n/g, '\n').replace(/\\r/g, '').replace(/\r\n/g, '\n').replace(/\r/g, '\n').trim()
  const header = (pem.match(/-----BEGIN[^-]+-----/) ?? [])[0] ?? '-----BEGIN PRIVATE KEY-----'
  const footer = (pem.match(/-----END[^-]+-----/) ?? [])[0] ?? '-----END PRIVATE KEY-----'
  const body = pem.replace(/-----BEGIN[^-]+-----/, '').replace(/-----END[^-]+-----/, '').replace(/\s+/g, '')
  const wrapped = (body.match(/.{1,64}/g) ?? []).join('\n')
  return `${header}\n${wrapped}\n${footer}`
}

async function fetchAppleStats(): Promise<AppleStats | null> {
  const issuerId = process.env.ASC_ISSUER_ID
  const keyId = process.env.ASC_KEY_ID
  const privateKeyPem = process.env.ASC_PRIVATE_KEY ? normalizePem(process.env.ASC_PRIVATE_KEY) : undefined
  const appId = process.env.ASC_APP_ID
  if (!issuerId || !keyId || !privateKeyPem || !appId) return null

  try {
    const privateKey = await importPKCS8(privateKeyPem, 'ES256')
    const token = await new SignJWT({})
      .setProtectedHeader({ alg: 'ES256', kid: keyId })
      .setIssuer(issuerId)
      .setIssuedAt()
      .setExpirationTime('20m')
      .setAudience('appstoreconnect-v1')
      .sign(privateKey)

    const headers = { Authorization: `Bearer ${token}` }
    const opts = { headers, next: { revalidate: 3600 } } as RequestInit

    // Step 1: get groups and builds in parallel
    const [buildsRes, groupsRes] = await Promise.all([
      fetch(`https://api.appstoreconnect.apple.com/v1/builds?filter[app]=${appId}&limit=1`, opts),
      fetch(`https://api.appstoreconnect.apple.com/v1/betaGroups?filter[app]=${appId}&fields[betaGroups]=name,isInternalGroup,publicLink,publicLinkEnabled`, opts),
    ])

    type GroupsPayload = { data?: { id: string; attributes: { name: string; isInternalGroup: boolean; publicLink?: string; publicLinkEnabled?: boolean } }[] }
    let groupsData: GroupsPayload | null = null
    let groupsDebugError: string | undefined
    if (groupsRes.ok) {
      groupsData = await groupsRes.json() as GroupsPayload
    } else {
      const body = await groupsRes.text().catch(() => '(unreadable)')
      groupsDebugError = `betaGroups HTTP ${groupsRes.status}: ${body.slice(0, 300)}`
    }

    const buildsData = buildsRes.ok ? await buildsRes.json() : null

    const groups = groupsData?.data ?? []
    const externalGroup = groups.find((g) => !g.attributes.isInternalGroup)

    // Step 2: count testers by total and invite type in parallel
    let groupTesterCount: number | null = null
    let emailTesterCount: number | null = null
    let publicLinkTesterCount: number | null = null
    if (externalGroup?.id) {
      try {
        const gid = externalGroup.id
        const base = `https://api.appstoreconnect.apple.com/v1/betaTesters?filter[betaGroups]=${gid}&limit=1`
        const [totalRes, emailRes, plRes] = await Promise.all([
          fetch(base, opts),
          fetch(`${base}&filter[inviteType]=EMAIL`, opts),
          fetch(`${base}&filter[inviteType]=PUBLIC_LINK`, opts),
        ])
        if (totalRes.ok) groupTesterCount = (await totalRes.json())?.meta?.paging?.total ?? null
        if (emailRes.ok) emailTesterCount = (await emailRes.json())?.meta?.paging?.total ?? null
        if (plRes.ok) publicLinkTesterCount = (await plRes.json())?.meta?.paging?.total ?? null
      } catch {
        // non-fatal — still return other data
      }
    }

    return {
      totalTesters: groupTesterCount,
      emailTesters: emailTesterCount,
      publicLinkTesters: publicLinkTesterCount,
      totalBuilds: buildsData?.meta?.paging?.total ?? null,
      externalGroupName: externalGroup?.attributes?.name ?? null,
      publicLink: externalGroup?.attributes?.publicLink ?? null,
      publicLinkEnabled: externalGroup?.attributes?.publicLinkEnabled ?? null,
      debugError: groupsDebugError,
    }
  } catch (e) {
    return { totalTesters: null, emailTesters: null, publicLinkTesters: null, totalBuilds: null, externalGroupName: null, publicLink: null, publicLinkEnabled: null, debugError: String(e) }
  }
}

async function hogql(query: string): Promise<unknown[][]> {
  const res = await fetch(`${POSTHOG_HOST}/api/projects/${PROJECT_ID}/query/`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${PERSONAL_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ query: { kind: 'HogQLQuery', query } }),
    next: { revalidate: 60 },
  })
  if (!res.ok) throw new Error(`PostHog ${res.status}: ${await res.text()}`)
  const json = await res.json()
  return json.results as unknown[][]
}

export async function GET(request: NextRequest) {
  if (!PROJECT_ID || !PERSONAL_KEY) {
    return NextResponse.json({ error: 'PostHog credentials not configured' }, { status: 503 })
  }

  const appleStats = await fetchAppleStats()

  const { searchParams } = new URL(request.url)
  const range = Math.min(Math.max(parseInt(searchParams.get('range') ?? '30'), 7), 365)
  const distribution = searchParams.get('dist') ?? 'all' // 'all' | 'testflight' | 'appstore'

  const knownDists = ['testflight', 'appstore', 'development']
  const distFilter = knownDists.includes(distribution)
    ? `AND properties.distribution = '${distribution}'`
    : ''

  try {
    const [usersRows, sessionsRows, featureRows, summaryRows, omdbRows, recentUsersRows, recentActivityRows] = await Promise.all([
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
          'friend_profile_viewed','collection_browsed',
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

      // Recent users: most recently first-seen within range
      hogql(`
        SELECT distinct_id, min(timestamp) AS first_seen, anyLast(properties.distribution) AS distribution
        FROM events
        WHERE timestamp >= now() - INTERVAL ${range} DAY ${distFilter}
        GROUP BY distinct_id
        ORDER BY first_seen DESC
        LIMIT 50
      `),

      // Recent activity: latest feature events
      hogql(`
        SELECT event, timestamp, distinct_id, properties.distribution AS distribution
        FROM events
        WHERE event IN (
          'tab_viewed','pick_for_me_started','pick_for_me_completed',
          'describe_it_used','cinema_search_used','search_performed',
          'item_detail_viewed','item_added','item_rated','friend_added',
          'friend_profile_viewed','collection_browsed',
          'trailer_opened','streaming_checked','external_rating_fetched'
        )
        AND timestamp >= now() - INTERVAL ${range} DAY ${distFilter}
        ORDER BY timestamp DESC
        LIMIT 100
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
    const recentUsers = recentUsersRows.map(([distinct_id, first_seen, distribution]) => ({
      distinct_id: String(distinct_id),
      first_seen: String(first_seen),
      distribution: distribution ? String(distribution) : null,
    }))
    const recentActivity = recentActivityRows.map(([event, timestamp, distinct_id, distribution]) => ({
      event: FEATURE_LABELS[event as string] ?? String(event),
      rawEvent: String(event),
      timestamp: String(timestamp),
      distinct_id: String(distinct_id),
      distribution: distribution ? String(distribution) : null,
    }))

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
      apple: appleStats,
      summary: {
        totalUsers: Number(totalUsers),
        totalSessions: Number(totalSessions),
        totalEvents: Number(totalEvents),
      },
      users,
      sessions,
      features,
      recentUsers,
      recentActivity,
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
