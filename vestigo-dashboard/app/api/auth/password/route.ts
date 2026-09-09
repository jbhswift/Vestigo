import { NextRequest, NextResponse } from 'next/server'
import { createSession, SESSION_COOKIE, sessionCookieOptions } from '../../../lib/auth'

export const dynamic = 'force-dynamic'

export async function POST(request: NextRequest) {
  const { password } = await request.json()
  const validPassword = process.env.DASHBOARD_PASSWORD

  if (!validPassword || password !== validPassword) {
    return NextResponse.json({ error: 'Incorrect password' }, { status: 401 })
  }

  const token = await createSession()
  const res = NextResponse.json({ ok: true })
  res.cookies.set(SESSION_COOKIE, token, sessionCookieOptions())
  return res
}
