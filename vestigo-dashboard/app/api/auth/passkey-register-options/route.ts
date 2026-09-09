import { NextRequest, NextResponse } from 'next/server'
import { generateRegistrationOptions } from '@simplewebauthn/server'
import { isoUint8Array } from '@simplewebauthn/server/helpers'
import { listCredentials } from '../../../lib/credentials'
import { createChallengeToken, CHALLENGE_COOKIE } from '../../../lib/auth'

export const dynamic = 'force-dynamic'

export async function POST(request: NextRequest) {
  // Require current password before allowing passkey registration
  const { password } = await request.json()
  const validPassword = process.env.DASHBOARD_PASSWORD
  if (validPassword && password !== validPassword) {
    return NextResponse.json({ error: 'Invalid password' }, { status: 401 })
  }

  const rpID = process.env.RP_ID ?? new URL(request.url).hostname
  const existing = await listCredentials()

  const options = await generateRegistrationOptions({
    rpName: 'Vestigo Dashboard',
    rpID,
    userID: isoUint8Array.fromUTF8String('vestigo-admin'),
    userName: 'admin',
    attestationType: 'none',
    excludeCredentials: existing.map(c => ({ id: c.credential_id, type: 'public-key' as const })),
    authenticatorSelection: {
      authenticatorAttachment: 'platform',
      userVerification: 'required',
      residentKey: 'preferred',
    },
  })

  const challengeToken = await createChallengeToken(options.challenge)
  const res = NextResponse.json(options)
  res.cookies.set(CHALLENGE_COOKIE, challengeToken, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict',
    maxAge: 300,
    path: '/',
  })
  return res
}
