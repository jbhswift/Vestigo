"use client";

import { useEffect, useRef, useState } from "react";
import { TMDB_BACKEND, TMDbItem } from "@/lib/tmdb";
import { MediaCard } from "./MediaCard";
import { MediaRow } from "./MediaRow";

export function HomeContent({
  trending,
  newReleases,
  upcoming,
}: {
  trending: TMDbItem[];
  newReleases: TMDbItem[];
  upcoming: TMDbItem[];
}) {
  const [query, setQuery] = useState("");
  const [results, setResults] = useState<TMDbItem[] | null>(null);
  const [loading, setLoading] = useState(false);
  const debounceRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  useEffect(() => {
    clearTimeout(debounceRef.current);
    const trimmed = query.trim();
    if (!trimmed) {
      setResults(null);
      setLoading(false);
      return;
    }
    setLoading(true);
    debounceRef.current = setTimeout(async () => {
      try {
        const params = new URLSearchParams({ path: "/search/multi", query: trimmed });
        const res = await fetch(`${TMDB_BACKEND}/tmdb-proxy?${params.toString()}`);
        const data = await res.json();
        const items: TMDbItem[] = (data.results ?? []).filter(
          (item: TMDbItem) => item.media_type === "movie" || item.media_type === "tv"
        );
        setResults(items);
      } catch {
        setResults([]);
      } finally {
        setLoading(false);
      }
    }, 400);
    return () => clearTimeout(debounceRef.current);
  }, [query]);

  const searching = query.trim().length > 0;

  return (
    <>
      <div className="search-box-wrap fade-in is-visible">
        <div className="search-box glass">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="10.5" cy="10.5" r="6.5" />
            <path d="M20 20l-4.8-4.8" />
          </svg>
          <input
            type="search"
            placeholder="Search movies and TV shows"
            autoComplete="off"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>
      </div>

      {searching ? (
        <div className="feature-group">
          {loading && <p className="small row-loading">Searching…</p>}
          {!loading && results && results.length === 0 && (
            <p className="small row-error">No results for &quot;{query}&quot;.</p>
          )}
          {!loading && results && results.length > 0 && (
            <div className="media-row media-row-wrap">
              {results.map((item) => (
                <MediaCard key={`${item.media_type}-${item.id}`} item={item} fallbackKind="movie" />
              ))}
            </div>
          )}
        </div>
      ) : (
        <>
          <MediaRow title="Trending now" items={trending} fallbackKind="movie" />
          <MediaRow title="New releases" items={newReleases} fallbackKind="movie" />
          <MediaRow title="Upcoming releases" items={upcoming} fallbackKind="movie" />
        </>
      )}
    </>
  );
}
