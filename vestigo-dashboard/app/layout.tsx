import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: 'Vestigo Dashboard',
  description: 'Analytics and API monitoring for Vestigo',
}

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body className="min-h-screen bg-[#09090b] text-zinc-100 antialiased">{children}</body>
    </html>
  )
}
