import { SignJWT, jwtVerify } from 'jose'
import { cookies } from 'next/headers'

const SESSION_COOKIE = 'dashboard_session'
const CHALLENGE_COOKIE = 'passkey_challenge'
const SESSION_DAYS = 7

function secret() {
  const s = process.env.DASHBOARD_JWT_SECRET
  if (!s) throw new Error('DASHBOARD_JWT_SECRET not configured')
  return new TextEncoder().encode(s)
}

export async function createSession(): Promise<string> {
  return new SignJWT({ role: 'admin' })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime(`${SESSION_DAYS}d`)
    .sign(secret())
}

export async function verifySession(token: string): Promise<boolean> {
  try {
    await jwtVerify(token, secret())
    return true
  } catch {
    return false
  }
}

export function sessionCookieOptions() {
  return {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict' as const,
    maxAge: SESSION_DAYS * 24 * 60 * 60,
    path: '/',
  }
}

export async function createChallengeToken(challenge: string): Promise<string> {
  return new SignJWT({ challenge })
    .setProtectedHeader({ alg: 'HS256' })
    .setExpirationTime('5m')
    .sign(secret())
}

export async function consumeChallenge(): Promise<string | null> {
  try {
    const cookieStore = await cookies()
    const token = cookieStore.get(CHALLENGE_COOKIE)?.value
    if (!token) return null
    const { payload } = await jwtVerify(token, secret())
    return (payload.challenge as string) ?? null
  } catch {
    return null
  }
}

export { SESSION_COOKIE, CHALLENGE_COOKIE }
