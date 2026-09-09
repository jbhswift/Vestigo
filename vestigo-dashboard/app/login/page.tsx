'use client'

import { useEffect, useState } from 'react'
import { startAuthentication, startRegistration, browserSupportsWebAuthn } from '@simplewebauthn/browser'

type Mode = 'idle' | 'loading' | 'password' | 'register'

export default function LoginPage() {
  const [mode, setMode] = useState<Mode>('idle')
  const [hasPasskeys, setHasPasskeys] = useState<boolean | null>(null)
  const [supportsWebAuthn, setSupportsWebAuthn] = useState(false)
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [status, setStatus] = useState<string | null>(null)

  const from = typeof window !== 'undefined'
    ? new URLSearchParams(window.location.search).get('from') ?? '/'
    : '/'

  useEffect(() => {
    setSupportsWebAuthn(browserSupportsWebAuthn())
    fetch('/api/auth/passkey-login-options')
      .then(r => r.json())
      .then(d => setHasPasskeys(d.hasCredentials ?? false))
      .catch(() => setHasPasskeys(false))
  }, [])

  async function signInWithPasskey() {
    setError(null)
    setMode('loading')
    setStatus('Fetching challenge…')
    try {
      const optRes = await fetch('/api/auth/passkey-login-options')
      if (!optRes.ok) throw new Error('Failed to get options')
      const { options } = await optRes.json()

      setStatus('Waiting for biometric…')
      const assertion = await startAuthentication({ optionsJSON: options })

      setStatus('Verifying…')
      const verRes = await fetch('/api/auth/passkey-login-verify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(assertion),
      })
      const verData = await verRes.json()
      if (!verRes.ok || !verData.ok) throw new Error(verData.error ?? 'Verification failed')

      window.location.href = from
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e)
      if (msg.includes('cancelled') || msg.includes('abort') || msg.includes('NotAllowed')) {
        setError('Biometric prompt was cancelled.')
      } else {
        setError(msg)
      }
      setMode('idle')
      setStatus(null)
    }
  }

  async function registerPasskey() {
    setError(null)
    setMode('loading')
    setStatus('Verifying password…')
    try {
      const optRes = await fetch('/api/auth/passkey-register-options', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password }),
      })
      if (!optRes.ok) {
        const d = await optRes.json()
        throw new Error(d.error ?? 'Password incorrect')
      }

      setStatus('Waiting for biometric…')
      const attResp = await startRegistration({ optionsJSON: await optRes.json() })

      setStatus('Saving passkey…')
      const verRes = await fetch('/api/auth/passkey-register-verify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(attResp),
      })
      const verData = await verRes.json()
      if (!verRes.ok || !verData.ok) throw new Error(verData.error ?? 'Registration failed')

      window.location.href = from
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e)
      if (msg.includes('cancelled') || msg.includes('abort') || msg.includes('NotAllowed')) {
        setError('Biometric prompt was cancelled.')
      } else {
        setError(msg)
      }
      setMode('register')
      setStatus(null)
    }
  }

  async function signInWithPassword() {
    setError(null)
    setMode('loading')
    try {
      const res = await fetch('/api/auth/password', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password }),
      })
      const data = await res.json()
      if (!res.ok || !data.ok) throw new Error(data.error ?? 'Incorrect password')
      window.location.href = from
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : String(e))
      setMode('password')
    }
  }

  const isLoading = mode === 'loading'

  return (
    <div className="min-h-screen flex items-center justify-center p-4">
      <div className="w-full max-w-sm">
        <div className="text-center mb-8">
          <h1 className="text-2xl font-bold text-zinc-100">Vestigo Dashboard</h1>
          <p className="text-zinc-500 text-sm mt-1">Sign in to continue</p>
        </div>

        <div className="card space-y-4">
          {error && (
            <div className="text-sm text-red-400 bg-red-950/30 border border-red-900/50 rounded-lg px-3 py-2">
              {error}
            </div>
          )}

          {isLoading && status && (
            <div className="text-sm text-zinc-400 text-center py-2">{status}</div>
          )}

          {/* Passkey section */}
          {!isLoading && supportsWebAuthn && hasPasskeys && mode !== 'register' && (
            <button
              onClick={signInWithPasskey}
              className="w-full flex items-center justify-center gap-2.5 bg-zinc-100 hover:bg-white text-zinc-900 font-semibold rounded-xl py-3 px-4 transition-colors"
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="12" cy="8" r="4"/><path d="M6 20v-2a4 4 0 0 1 4-4h2"/><path d="m19 16-2 2 4 4"/><path d="m17 22 2-2"/>
              </svg>
              Sign in with passkey
            </button>
          )}

          {/* Register passkey (no passkeys yet) */}
          {!isLoading && supportsWebAuthn && hasPasskeys === false && mode !== 'password' && mode !== 'register' && (
            <button
              onClick={() => { setMode('register'); setError(null) }}
              className="w-full flex items-center justify-center gap-2.5 bg-indigo-600 hover:bg-indigo-500 text-white font-semibold rounded-xl py-3 px-4 transition-colors"
            >
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/>
              </svg>
              Set up passkey
            </button>
          )}

          {/* Register form */}
          {!isLoading && mode === 'register' && (
            <div className="space-y-3">
              <p className="text-xs text-zinc-500">Enter your password to authorise passkey registration</p>
              <input
                type="password"
                placeholder="Current password"
                value={password}
                onChange={e => setPassword(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && registerPasskey()}
                autoFocus
                className="w-full bg-zinc-800 border border-zinc-700 rounded-xl px-4 py-3 text-sm text-zinc-100 placeholder-zinc-500 focus:outline-none focus:border-indigo-500"
              />
              <button
                onClick={registerPasskey}
                disabled={!password}
                className="w-full bg-indigo-600 hover:bg-indigo-500 disabled:opacity-40 disabled:cursor-not-allowed text-white font-semibold rounded-xl py-3 px-4 transition-colors"
              >
                Continue
              </button>
              <button onClick={() => { setMode('password'); setError(null) }} className="w-full text-sm text-zinc-500 hover:text-zinc-300 py-1 transition-colors">
                Use password instead
              </button>
            </div>
          )}

          {/* Divider between passkey and password */}
          {!isLoading && supportsWebAuthn && hasPasskeys && mode !== 'password' && (
            <div className="flex items-center gap-3">
              <div className="flex-1 h-px bg-zinc-800" />
              <span className="text-xs text-zinc-600">or</span>
              <div className="flex-1 h-px bg-zinc-800" />
            </div>
          )}

          {/* Password form */}
          {!isLoading && (mode === 'password' || (!supportsWebAuthn && mode !== 'register')) && (
            <div className="space-y-3">
              <input
                type="password"
                placeholder="Password"
                value={password}
                onChange={e => setPassword(e.target.value)}
                onKeyDown={e => e.key === 'Enter' && signInWithPassword()}
                autoFocus={mode === 'password'}
                className="w-full bg-zinc-800 border border-zinc-700 rounded-xl px-4 py-3 text-sm text-zinc-100 placeholder-zinc-500 focus:outline-none focus:border-indigo-500"
              />
              <button
                onClick={signInWithPassword}
                disabled={!password}
                className="w-full bg-zinc-700 hover:bg-zinc-600 disabled:opacity-40 disabled:cursor-not-allowed text-zinc-100 font-semibold rounded-xl py-3 px-4 transition-colors"
              >
                Sign in
              </button>
              {supportsWebAuthn && hasPasskeys && (
                <button onClick={() => { setMode('idle'); setError(null) }} className="w-full text-sm text-zinc-500 hover:text-zinc-300 py-1 transition-colors">
                  ← Back
                </button>
              )}
            </div>
          )}

          {/* Show password button when passkey is primary */}
          {!isLoading && supportsWebAuthn && hasPasskeys && mode === 'idle' && (
            <button
              onClick={() => { setMode('password'); setError(null) }}
              className="w-full text-sm text-zinc-500 hover:text-zinc-300 py-1 transition-colors"
            >
              Use password instead
            </button>
          )}
        </div>
      </div>
    </div>
  )
}
