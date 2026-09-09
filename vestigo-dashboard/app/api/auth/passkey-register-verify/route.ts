import { NextRequest, NextResponse } from 'next/server'
import { verifyRegistrationResponse } from '@simplewebauthn/server'
import { isoBase64URL } from '@simplewebauthn/server/helpers'
import { saveCredential } from '../../../lib/credentials'
import { consumeChallenge, createSession, SESSION_COOKIE, sessionCookieOptions, CHALLENGE_COOKIE } from '../../../lib/auth'

export const dynamic = 'force-dynamic'

export async function POST(request: NextRequest) {
  const body = await request.json()
  const rpID = process.env.RP_ID ?? new URL(request.url).hostname
  const origin = process.env.RP_ORIGIN ?? request.headers.get('origin') ?? `https://${rpID}`

  const challenge = await consumeChallenge()
  if (!challenge) {
    return NextResponse.json({ error: 'Challenge expired or missing — try again' }, { status: 400 })
  }

  try {
    const verification = await verifyRegistrationResponse({
      response: body,
      expectedChallenge: challenge,
      expectedOrigin: origin,
      expectedRPID: rpID,
    })

    if (!verification.verified || !verification.registrationInfo) {
      return NextResponse.json({ error: 'Verification failed' }, { status: 400 })
    }

    // In v14: credential.id is already Base64URLString; credential.publicKey is Uint8Array
    const { credential } = verification.registrationInfo
    await saveCredential({
      credential_id: credential.id,
      public_key: isoBase64URL.fromBuffer(credential.publicKey),
      counter: credential.counter,
    })

    const token = await createSession()
    const res = NextResponse.json({ ok: true })
    res.cookies.set(SESSION_COOKIE, token, sessionCookieOptions())
    res.cookies.delete(CHALLENGE_COOKIE)
    return res
  } catch (e) {
    return NextResponse.json({ error: String(e) }, { status: 400 })
  }
}
