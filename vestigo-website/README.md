# vestigo-website

Next.js replacement for the static `vestigo-app.com` site, built specifically to support real server-rendered link previews (Open Graph / Twitter Card) for shared items — something the previous GitHub Pages–hosted static site structurally could not do, since link-preview crawlers don't execute JavaScript.

Live at **https://vestigo-app.com** (also at https://vestigo-website.vercel.app).

## Structure

The site is intentionally just a download page now — no browsing/search UI. The earlier, fuller version (Home tab with search + carousels, a richer Download tab with screenshots/About) is preserved, not deleted, in `app/_disabled/` (excluded from routing by the `_` prefix — Next.js ignores it). Revive by moving `app/_disabled/home-page.tsx.bak` back to `app/page.tsx` and `app/_disabled/download-full/` back to `app/download/`.

- `/` (`app/page.tsx`) — the whole site. A moving wall of movie posters as the background (`components/PosterMarquee.tsx`, data from `public/posters/manifest.json`), dimmed to 0.35 opacity, with the app icon, name, and a TestFlight download button centered on top. Posters are pulled from TMDb's `/discover/movie` sorted by `vote_average.desc` with a `vote_count.gte` floor — the plain `/movie/top_rated` endpoint has no vote-count floor and gets swamped by niche titles with a handful of 10-star votes outranking things like The Godfather. 250 unique posters are split into disjoint rows (`splitIntoRows` in `PosterMarquee.tsx`), so no title is ever on screen twice at once regardless of scroll position. Refresh the pool with `python3 scripts/fetch-posters.py`.
- `/media` (`app/media/page.tsx`) — shared-item landing page, reached via `?id=&kind=` (same shape as `MediaItem.shareURL` in the app and the AASA `/media*` universal link rule — **do not change this URL shape** without updating the Swift app too). Mirrors `DetailView.swift`: poster/title/meta, overview, cast, trailer, streaming providers, similar titles. `generateMetadata()` fetches TMDb data server-side so shared links get a real per-movie title/poster/description preview. Shows a small `<Nav/>` (single link back to `/`) since it's a page people land on from outside the site.
- `/friend` (`app/friend/page.tsx`) — friend-invite landing page, reached via `?t=<opaque token>` (matches `create_invite`'s token shape and `ContentView.swift`'s link handling). Deliberately generic/unpersonalized — a web visitor has no Supabase session, so there's no way to verify an inviter's name here the way the native app's authenticated `get_invite_preview` RPC does. Also shows `<Nav/>`.
- Every page has a full-width "Open in Vestigo" button (`components/OpenInVestigoButton.tsx`) that tries the `vestigo://` custom scheme and falls back to TestFlight after ~1.5s if the app doesn't open — it never fires automatically, only on a tap.

## Pending

- **App screenshots / richer Download content** — on hold in `app/_disabled/download-full/`. Revisit once real Simulator/device screenshots are available (automated capture was tried and rejected — empty/sign-in states don't sell the app).
- **Apple Smart App Banner / `apple-itunes-app` meta tag** — intentionally left out. Needs a real numeric App Store Connect app ID, which doesn't exist yet (TestFlight-only). Add it to `app/layout.tsx` metadata once the app has a public App Store listing.

## Deploying

```
npx vercel deploy --prod
```

Uses the Vercel CLI auth already configured on this machine (same account as `vestigo-dashboard`).
