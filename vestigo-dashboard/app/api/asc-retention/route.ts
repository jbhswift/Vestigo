import { NextResponse } from 'next/server'
import { SignJWT, importPKCS8 } from 'jose'
import { createGunzip } from 'zlib'
import { Readable } from 'stream'

export const dynamic = 'force-dynamic'

// App Store Connect Analytics Reports API
// Flow: get/create ONGOING report request → list reports → get instances → get segments → download TSV

const APP_STORE_ENGAGEMENT = 'APP_STORE_ENGAGEMENT'

export interface ASCRetentionData {
  sessionsPerActiveDevice: number | null  // avg sessions per device (proxy for D1+ retention behaviour)
  activeDevices30d: number | null
  activeDevices7d: number | null
  activeDevices1d: number | null
  reportDate: string | null              // date of the most recent data point
  error?: string
}

function normalizePem(raw: string): string {
  // Unescape literal \n sequences that Vercel may store
  const pem = raw.replace(/\\n/g, '\n').replace(/\\r/g, '').replace(/\r\n/g, '\n').replace(/\r/g, '\n').trim()
  const header = (pem.match(/-----BEGIN[^-]+-----/) ?? [])[0] ?? '-----BEGIN PRIVATE KEY-----'
  const footer = (pem.match(/-----END[^-]+-----/) ?? [])[0] ?? '-----END PRIVATE KEY-----'
  // Always strip all whitespace from the body and re-wrap at 64 chars
  const body = pem.replace(/-----BEGIN[^-]+-----/, '').replace(/-----END[^-]+-----/, '').replace(/\s+/g, '')
  const wrapped = (body.match(/.{1,64}/g) ?? []).join('\n')
  return `${header}\n${wrapped}\n${footer}`
}

async function makeToken(): Promise<string> {
  const issuerId = process.env.ASC_ISSUER_ID!
  const keyId = process.env.ASC_KEY_ID!
  const privateKeyPem = normalizePem(process.env.ASC_PRIVATE_KEY!)
  const privateKey = await importPKCS8(privateKeyPem, 'ES256')
  return new SignJWT({})
    .setProtectedHeader({ alg: 'ES256', kid: keyId })
    .setIssuer(issuerId)
    .setIssuedAt()
    .setExpirationTime('20m')
    .setAudience('appstoreconnect-v1')
    .sign(privateKey)
}

function ascFetch(url: string, token: string) {
  return fetch(url, {
    headers: { Authorization: `Bearer ${token}` },
    next: { revalidate: 3600 },
  })
}

async function decompressGzip(buffer: ArrayBuffer): Promise<string> {
  return new Promise((resolve, reject) => {
    const gunzip = createGunzip()
    const chunks: Buffer[] = []
    const readable = Readable.from(Buffer.from(buffer))
    readable.pipe(gunzip)
    gunzip.on('data', (chunk: Buffer) => chunks.push(chunk))
    gunzip.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')))
    gunzip.on('error', reject)
  })
}

type TSVRow = Record<string, string>

function parseTSV(text: string): TSVRow[] {
  const lines = text.split('\n').filter(Boolean)
  if (lines.length < 2) return []
  const headers = lines[0].split('\t')
  return lines.slice(1).map(line => {
    const cols = line.split('\t')
    const row: TSVRow = {}
    headers.forEach((h, i) => { row[h.trim()] = (cols[i] ?? '').trim() })
    return row
  })
}

async function getOrCreateReportRequest(appId: string, token: string): Promise<string | null> {
  // Check for existing ONGOING request
  const listRes = await ascFetch(
    `https://api.appstoreconnect.apple.com/v1/apps/${appId}/analyticsReportRequests?filter[accessType]=ONGOING`,
    token,
  )
  if (listRes.ok) {
    type RequestPayload = { data?: { id: string }[] }
    const d = await listRes.json() as RequestPayload
    if (d.data && d.data.length > 0) return d.data[0].id
  }

  // Create one
  const createRes = await fetch('https://api.appstoreconnect.apple.com/v1/analyticsReportRequests', {
    method: 'POST',
    headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      data: {
        type: 'analyticsReportRequests',
        attributes: { accessType: 'ONGOING' },
        relationships: { app: { data: { type: 'apps', id: appId } } },
      },
    }),
  })
  if (!createRes.ok) return null
  type CreatePayload = { data?: { id: string } }
  const created = await createRes.json() as CreatePayload
  return created.data?.id ?? null
}

async function getEngagementReport(requestId: string, token: string): Promise<string | null> {
  const res = await ascFetch(
    `https://api.appstoreconnect.apple.com/v1/analyticsReportRequests/${requestId}/reports?filter[reportType]=${APP_STORE_ENGAGEMENT}`,
    token,
  )
  if (!res.ok) return null
  type ReportsPayload = { data?: { id: string }[] }
  const d = await res.json() as ReportsPayload
  return d.data?.[0]?.id ?? null
}

async function getMostRecentInstance(reportId: string, token: string): Promise<string | null> {
  // granularity DAILY gives per-day rows — get the latest instance
  const res = await ascFetch(
    `https://api.appstoreconnect.apple.com/v1/analyticsReports/${reportId}/instances?filter[granularity]=DAILY&sort=-processingDate&limit=1`,
    token,
  )
  if (!res.ok) return null
  type InstancesPayload = { data?: { id: string }[] }
  const d = await res.json() as InstancesPayload
  return d.data?.[0]?.id ?? null
}

async function getSegmentUrl(instanceId: string, token: string): Promise<string | null> {
  const res = await ascFetch(
    `https://api.appstoreconnect.apple.com/v1/analyticsReportInstances/${instanceId}/segments`,
    token,
  )
  if (!res.ok) return null
  type SegmentsPayload = { data?: { attributes?: { url?: string } }[] }
  const d = await res.json() as SegmentsPayload
  return d.data?.[0]?.attributes?.url ?? null
}

function parseEngagementRows(rows: TSVRow[]): Omit<ASCRetentionData, 'error'> {
  // Sort descending by date to get most recent
  const sorted = [...rows].sort((a, b) =>
    (b['Date'] ?? b['date'] ?? '').localeCompare(a['Date'] ?? a['date'] ?? '')
  )

  const latest = sorted[0]
  if (!latest) return { sessionsPerActiveDevice: null, activeDevices30d: null, activeDevices7d: null, activeDevices1d: null, reportDate: null }

  // Column names vary by region/locale — try a few variants
  const parseNum = (row: TSVRow, ...keys: string[]): number | null => {
    for (const k of keys) {
      const v = row[k]
      if (v !== undefined && v !== '' && v !== '-') {
        const n = parseFloat(v)
        return isNaN(n) ? null : n
      }
    }
    return null
  }

  const sessionsPerDevice = parseNum(latest, 'Sessions Per Active Device', 'Sessions per Active Device')
  const activeDevices = parseNum(latest, 'Active Devices', 'Unique Devices')

  // Try to get 7d and 1d rolling data from the last 7 and 1 rows respectively
  const row7 = sorted[6]
  const row1 = sorted[0]

  return {
    sessionsPerActiveDevice: sessionsPerDevice,
    activeDevices30d: activeDevices,
    activeDevices7d: row7 ? parseNum(row7, 'Active Devices', 'Unique Devices') : null,
    activeDevices1d: row1 ? parseNum(row1, 'Active Devices', 'Unique Devices') : null,
    reportDate: latest['Date'] ?? latest['date'] ?? null,
  }
}

export async function GET(): Promise<NextResponse> {
  const appId = process.env.ASC_APP_ID
  const issuerId = process.env.ASC_ISSUER_ID
  const keyId = process.env.ASC_KEY_ID
  const privateKeyPem = process.env.ASC_PRIVATE_KEY

  if (!appId || !issuerId || !keyId || !privateKeyPem) {
    return NextResponse.json({ data: null, error: 'ASC credentials not configured' })
  }

  try {
    const token = await makeToken()

    const requestId = await getOrCreateReportRequest(appId, token)
    if (!requestId) return NextResponse.json({ data: null, error: 'Could not get/create report request' })

    const reportId = await getEngagementReport(requestId, token)
    if (!reportId) {
      // Report may still be generating (just created the request)
      return NextResponse.json({ data: null, error: 'Engagement report not yet available — check back in a few hours' })
    }

    const instanceId = await getMostRecentInstance(reportId, token)
    if (!instanceId) return NextResponse.json({ data: null, error: 'No report instances available yet' })

    const segmentUrl = await getSegmentUrl(instanceId, token)
    if (!segmentUrl) return NextResponse.json({ data: null, error: 'No segment URL found' })

    // Download and decompress gzip TSV (pre-signed URL, no auth needed)
    const dlRes = await fetch(segmentUrl)
    if (!dlRes.ok) return NextResponse.json({ data: null, error: `Download failed: ${dlRes.status}` })

    const buffer = await dlRes.arrayBuffer()
    const tsv = await decompressGzip(buffer)
    const rows = parseTSV(tsv)

    const data = parseEngagementRows(rows)
    return NextResponse.json({ data, updatedAt: new Date().toISOString() })
  } catch (e) {
    return NextResponse.json({ data: null, error: String(e) })
  }
}
