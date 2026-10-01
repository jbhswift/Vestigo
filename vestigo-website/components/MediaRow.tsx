"use client";

import { useEffect, useRef, useState } from "react";
import { TMDbItem } from "@/lib/tmdb";
import { MediaCard } from "./MediaCard";

const CARD_WIDTH = 120;
const CARD_GAP = 14;
const DESKTOP_BREAKPOINT = 700;
const MOBILE_LIMIT = 12;
const EXPANDED_LIMIT = 24;

export function MediaRow({
  title,
  items,
  fallbackKind,
}: {
  title: string;
  items: TMDbItem[];
  fallbackKind: "movie" | "tv";
}) {
  const rowRef = useRef<HTMLDivElement>(null);
  const [expanded, setExpanded] = useState(false);
  const [fitCount, setFitCount] = useState(items.length);
  const [isDesktop, setIsDesktop] = useState(false);

  useEffect(() => {
    function recompute() {
      const el = rowRef.current;
      if (!el) return;
      const desktop = window.innerWidth >= DESKTOP_BREAKPOINT;
      setIsDesktop(desktop);
      if (desktop) {
        const style = getComputedStyle(el);
        const available =
          el.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
        setFitCount(Math.max(1, Math.floor((available + CARD_GAP) / (CARD_WIDTH + CARD_GAP))));
      }
    }
    recompute();
    window.addEventListener("resize", recompute);
    return () => window.removeEventListener("resize", recompute);
  }, []);

  if (!items.length) return null;

  const visible = expanded
    ? items.slice(0, EXPANDED_LIMIT)
    : isDesktop
      ? items.slice(0, fitCount)
      : items.slice(0, MOBILE_LIMIT);

  const rowClass = [
    "media-row",
    expanded ? "media-row-wrap" : "",
    !expanded && isDesktop ? "media-row-center" : "",
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <div className="feature-group">
      <div
        className={`section-header${expanded ? " expanded" : ""}`}
        role="button"
        tabIndex={0}
        onClick={() => setExpanded((e) => !e)}
        onKeyDown={(e) => {
          if (e.key === "Enter" || e.key === " ") {
            e.preventDefault();
            setExpanded((v) => !v);
          }
        }}
      >
        <h2>{title}</h2>
        <svg
          className="chevron"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2.2"
          strokeLinecap="round"
          strokeLinejoin="round"
        >
          <path d="M9 6l6 6-6 6" />
        </svg>
      </div>
      <div className={rowClass} ref={rowRef}>
        {visible.map((item) => (
          <MediaCard key={item.id} item={item} fallbackKind={fallbackKind} />
        ))}
      </div>
    </div>
  );
}
