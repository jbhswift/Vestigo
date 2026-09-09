import { NextRequest, NextResponse } from 'next/server'
import { generateAuthenticationOptions } from '@simplewebauthn/server'
import { listCredentials } from '../../../lib/credentials'
import { createChallengeToken, CHALLENGE_COOKIE } from '../../../lib/auth'

export const dynamic = 'force-dynamic'

export async function GET(request: NextRequest) {
  const rpID = process.env.RP_ID ?? new URL(request.url).hostname
  const creds = await listCredentials()

  const options = await generateAuthenticationOptions({
    rpID,
    userVerification: 'required',
    allowCredentials: creds.map(c => ({ id: c.credential_id, type: 'public-key' as const })),
  })

  const challengeToken = await createChallengeToken(options.challenge)
  const res = NextResponse.json({ options, hasCredentials: creds.length > 0 })
  res.cookies.set(CHALLENGE_COOKIE, challengeToken, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict',
    maxAge: 300,
    path: '/',
  })
  return res
}
