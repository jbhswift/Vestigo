import { NextRequest, NextResponse } from 'next/server'
import { jwtVerify } from 'jose'

const SESSION_COOKIE = 'dashboard_session'

export async function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl

  // Allow static assets, login page, and auth API routes through
  if (
    pathname.startsWith('/_next/') ||
    pathname === '/favicon.ico' ||
    pathname.startsWith('/login') ||
    pathname.startsWith('/api/auth/')
  ) {
    return NextResponse.next()
  }

  const secret = process.env.DASHBOARD_JWT_SECRET
  // If secret not configured, fall back to old Basic Auth for safety
  if (!secret) {
    const validPassword = process.env.DASHBOARD_PASSWORD
    if (!validPassword) return NextResponse.next()
    const auth = request.headers.get('authorization')
    if (auth?.startsWith('Basic ')) {
      const decoded = Buffer.from(auth.slice(6), 'base64').toString('utf-8')
      const [, password] = decoded.split(':')
      if (password === validPassword) return NextResponse.next()
    }
    return new NextResponse('Unauthorized', {
      status: 401,
      headers: { 'WWW-Authenticate': 'Basic realm="Vestigo Dashboard"' },
    })
  }

  const token = request.cookies.get(SESSION_COOKIE)?.value
  if (token) {
    try {
      await jwtVerify(token, new TextEncoder().encode(secret))
      return NextResponse.next()
    } catch { /* invalid or expired — fall through to redirect */ }
  }

  const loginUrl = request.nextUrl.clone()
  loginUrl.pathname = '/login'
  loginUrl.searchParams.set('from', pathname)
  return NextResponse.redirect(loginUrl)
}

export const config = {
  matcher: ['/((?!_next/static|_next/image|favicon.ico).*)'],
}
