#!/usr/bin/env python3
"""Refreshes public/posters/ with real acclaimed-film posters for PosterMarquee.

Uses /discover/movie sorted by vote_average.desc with a vote_count floor,
NOT /movie/top_rated — the latter has no vote-count minimum and gets swamped
by niche titles with a handful of 10-star votes outranking things like The
Godfather. This mirrors what IMDb's own weighted-rating methodology is
actually for: a minimum-votes floor before ranking by score.

Run from the vestigo-website directory: python3 scripts/fetch-posters.py
"""
import json
import os
import urllib.request

BACKEND = "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api/tmdb-proxy"
VOTE_COUNT_FLOOR = 5000
TARGET_COUNT = 250
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "public", "posters")


def fetch_top_films():
    items, seen = [], set()
    page = 1
    while len(items) < TARGET_COUNT:
        url = (
            f"{BACKEND}?path=%2Fdiscover%2Fmovie&sort_by=vote_average.desc"
            f"&vote_count.gte={VOTE_COUNT_FLOOR}&page={page}"
        )
        with urllib.request.urlopen(url, timeout=15) as r:
            data = json.loads(r.read())
        results = data.get("results", [])
        if not results:
            break
        for item in results:
            if item["id"] not in seen:
                seen.add(item["id"])
                items.append(item)
        print(f"page {page}: {len(items)} unique so far")
        page += 1
    return items[:TARGET_COUNT]


def download_posters(items):
    os.makedirs(OUT_DIR, exist_ok=True)
    manifest = []
    for item in items:
        poster_path = item.get("poster_path")
        if not poster_path:
            continue
        filename = f"{item['id']}.jpg"
        dest = os.path.join(OUT_DIR, filename)
        if not os.path.exists(dest):
            try:
                urllib.request.urlretrieve(
                    f"https://image.tmdb.org/t/p/w342{poster_path}", dest
                )
            except Exception as e:  # noqa: BLE001
                print("FAILED", item["id"], item.get("title"), e)
                continue
        manifest.append({"id": item["id"], "title": item.get("title"), "file": f"/posters/{filename}"})

    with open(os.path.join(OUT_DIR, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
    print(f"Saved {len(manifest)} posters to {OUT_DIR}")


if __name__ == "__main__":
    download_posters(fetch_top_films())
