"use client";

import Link from "next/link";

// The site is just the download page now (see app/page.tsx) — this is only
// used on /media and /friend, as a simple way back, not a multi-tab bar.
export function Nav() {
  return (
    <nav className="tabs">
      <div className="tab-bar">
        <Link className="tab-btn" href="/">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <path d="M3 11.5 12 4l9 7.5" />
            <path d="M5.5 10v9.5A1 1 0 0 0 6.5 20.5h11a1 1 0 0 0 1-1V10" />
          </svg>
          <span>Vestigo</span>
        </Link>
      </div>
    </nav>
  );
}
