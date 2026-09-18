import { NextResponse } from 'next/server'

export const dynamic = 'force-dynamic'

const SENTRY_TOKEN = process.env.SENTRY_AUTH_TOKEN
const SENTRY_ORG = process.env.SENTRY_ORG       // numeric org ID from DSN: o{ORG_ID}
const SENTRY_PROJECT = process.env.SENTRY_PROJECT // numeric project ID from DSN path

export interface SentryData {
  configured: boolean
  latestVersion: string | null
  crashes: number
  crashedUsers: number
  errors: number
  feedback: number
}

export async function GET() {
  if (!SENTRY_TOKEN || !SENTRY_ORG || !SENTRY_PROJECT) {
    return NextResponse.json<SentryData>({
      configured: false,
      latestVersion: null,
      crashes: 0,
      crashedUsers: 0,
      errors: 0,
      feedback: 0,
    })
  }

  const headers = { Authorization: `Bearer ${SENTRY_TOKEN}` }
  const opts = (revalidate: number) => ({ headers, next: { revalidate } }) as RequestInit

  try {
    // Use org-level releases endpoint with project filter — works reliably with numeric IDs
    const releasesRes = await fetch(
      `https://sentry.io/api/0/organizations/${SENTRY_ORG}/releases/?project=${SENTRY_PROJECT}&per_page=1`,
      opts(3600)
    )
    if (!releasesRes.ok) throw new Error(`Releases HTTP ${releasesRes.status}: ${await releasesRes.text()}`)
    const releases = await releasesRes.json() as { version: string }[]
    const latestVersion = releases[0]?.version ?? null

    if (!latestVersion) {
      return NextResponse.json<SentryData>({
        configured: true, latestVersion: null,
        crashes: 0, crashedUsers: 0, errors: 0, feedback: 0,
      })
    }

    const releaseParam = encodeURIComponent(latestVersion)
    const baseIssueUrl = `https://sentry.io/api/0/organizations/${SENTRY_ORG}/issues/?project=${SENTRY_PROJECT}&release=${releaseParam}&limit=100`

    const [crashRes, allIssuesRes, feedbackRes] = await Promise.all([
      fetch(`${baseIssueUrl}&query=level%3Afatal`, opts(300)),
      fetch(`${baseIssueUrl}&query=`, opts(300)),
      // User reports endpoint — scoped to project via query param
      fetch(`https://sentry.io/api/0/organizations/${SENTRY_ORG}/user-reports/?project=${SENTRY_PROJECT}&limit=100`, opts(300)),
    ])

    let crashes = 0
    let crashedUsers = 0
    if (crashRes.ok) {
      const issues = await crashRes.json() as { count: string; userCount: number }[]
      for (const issue of issues) {
        crashes += Number(issue.count ?? 0)
        crashedUsers += Number(issue.userCount ?? 0)
      }
    }

    let errors = 0
    if (allIssuesRes.ok) {
      const issues = await allIssuesRes.json() as { count: string }[]
      for (const issue of issues) {
        errors += Number(issue.count ?? 0)
      }
    }

    let feedback = 0
    if (feedbackRes.ok) {
      const fb = await feedbackRes.json()
      feedback = Array.isArray(fb) ? fb.length : 0
    }

    return NextResponse.json<SentryData>({
      configured: true,
      latestVersion,
      crashes,
      crashedUsers,
      errors,
      feedback,
    })
  } catch (e) {
    return NextResponse.json({ error: String(e) }, { status: 500 })
  }
}
