"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

export function Nav() {
  const pathname = usePathname();
  return (
    <nav className="tabs">
      <div className="tab-bar">
        <Link className={`tab-btn${pathname === "/download" ? " active" : ""}`} href="/download">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <path d="M12 3.5v11" />
            <path d="M8 10.5l4 4 4-4" />
            <path d="M4.5 17.5v2A1.5 1.5 0 0 0 6 21h12a1.5 1.5 0 0 0 1.5-1.5v-2" />
          </svg>
          <span>Download</span>
        </Link>
        <Link className={`tab-btn${pathname === "/" ? " active" : ""}`} href="/">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <path d="M3 11.5 12 4l9 7.5" />
            <path d="M5.5 10v9.5A1 1 0 0 0 6.5 20.5h11a1 1 0 0 0 1-1V10" />
          </svg>
          <span>Home</span>
        </Link>
      </div>
    </nav>
  );
}
