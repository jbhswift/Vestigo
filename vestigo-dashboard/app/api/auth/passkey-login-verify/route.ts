import { NextRequest, NextResponse } from 'next/server'
import { verifyAuthenticationResponse } from '@simplewebauthn/server'
import { isoBase64URL } from '@simplewebauthn/server/helpers'
import { findCredential, updateCounter } from '../../../lib/credentials'
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

  const credentialID = body.id as string
  const stored = await findCredential(credentialID)
  if (!stored) {
    return NextResponse.json({ error: 'Passkey not recognised' }, { status: 400 })
  }

  try {
    const verification = await verifyAuthenticationResponse({
      response: body,
      expectedChallenge: challenge,
      expectedOrigin: origin,
      expectedRPID: rpID,
      // In v14: WebAuthnCredential.id is Base64URLString; publicKey is Uint8Array
      credential: {
        id: stored.credential_id,
        publicKey: isoBase64URL.toBuffer(stored.public_key),
        counter: stored.counter,
      },
    })

    if (!verification.verified) {
      return NextResponse.json({ error: 'Verification failed' }, { status: 400 })
    }

    await updateCounter(stored.credential_id, verification.authenticationInfo.newCounter)

    const token = await createSession()
    const res = NextResponse.json({ ok: true })
    res.cookies.set(SESSION_COOKIE, token, sessionCookieOptions())
    res.cookies.delete(CHALLENGE_COOKIE)
    return res
  } catch (e) {
    return NextResponse.json({ error: String(e) }, { status: 400 })
  }
}
