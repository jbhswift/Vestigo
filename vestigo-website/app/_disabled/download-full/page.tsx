import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Download",
  description: "Download Vestigo on TestFlight.",
};

const ATTRIBUTIONS = [
  {
    name: "TMDB",
    url: "https://www.themoviedb.org/",
    desc: "This product uses the TMDB API but is not endorsed or certified by TMDB.",
  },
  {
    name: "Watchmode",
    url: "https://api.watchmode.com/",
    desc: "Streaming availability and provider data are provided in part by Watchmode.",
  },
  {
    name: "TheTVDB",
    url: "https://thetvdb.com/",
    desc: "Series, season, episode, and franchise metadata are provided in part by TheTVDB.",
  },
  {
    name: "OMDb",
    url: "https://www.omdbapi.com/",
    desc: "This product uses the OMDb API but is not endorsed or certified by OMDb or IMDb. Ratings and movie data are provided in part by The Open Movie Database and IMDb.",
  },
  {
    name: "YouTube",
    url: "https://www.youtube.com/",
    desc: "Trailer playback uses embedded YouTube videos where available.",
  },
  {
    name: "AMC Theatres",
    url: "https://www.amctheatres.com/",
    desc: "Cinema showtimes and theatre locations are provided by AMC Theatres.",
  },
  {
    name: "Wikidata and Wikipedia",
    url: "https://www.wikidata.org/",
    desc: "Original-media and knowledge links use Wikimedia projects and their content licenses.",
  },
];

// Placeholder frames until real Simulator captures are dropped in at
// /public/screenshots/*.png — see the follow-up step in this session.
const SCREENSHOT_LABELS = ["Home", "Detail view", "Watchlist", "Friends"];

export default function DownloadPage() {
  return (
    <main className="wrap" style={{ paddingBottom: 40 }}>
      <header className="hero fade-in is-visible">
        <img src="/vestigo-app-icon.png" alt="Vestigo app icon" className="app-icon" />
        <h1 className="title">Vestigo</h1>
        <p className="tagline">
          A personal movie and TV tracker for iOS. Discover what to watch next, track what
          you&apos;ve seen, and get recommendations that reflect your history.
        </p>
        <div className="hero-actions">
          <a
            className="btn btn-primary"
            href="https://testflight.apple.com/join/zbvP2WEx"
            target="_blank"
            rel="noopener noreferrer"
          >
            Download on TestFlight
          </a>
        </div>
        <p className="small">iOS 26.0 or later required.</p>
      </header>

      <div className="screenshots-section">
        <div className="screenshots-row">
          {SCREENSHOT_LABELS.map((label) => (
            <div className="screenshot-frame" key={label}>
              <div className="screenshot-placeholder">{label}</div>
            </div>
          ))}
        </div>
      </div>

      <div className="about-section fade-in is-visible">
        <h2>About</h2>
        <p className="sub">Created by Jojo Hyman.</p>
        <div className="about-links">
          <a className="btn btn-ghost" href="https://github.com/Kyrbiis/Vestigo" target="_blank" rel="noopener noreferrer">
            GitHub
          </a>
          <a className="btn btn-ghost" href="mailto:vestigosupport@gmail.com">
            Send Feedback
          </a>
        </div>
        <div className="about-disclaimers">
          <p>Your library and preferences are stored on-device and in iCloud where enabled.</p>
          <p>
            Vestigo was vibe coded: AI assisted with code implementation, while the product
            thinking, decisions, review, and non-coding work were all done by people.
          </p>
          <p>
            Vestigo is not affiliated with TMDB, IMDb, OMDb, TheTVDB, Watchmode, YouTube,
            Wikimedia, or their parent companies.
          </p>
        </div>

        <p className="sub attribution-intro">
          Vestigo combines catalog, ratings, recommendations, availability, trailer, and
          open-knowledge data from the following services:
        </p>
        <div className="attribution-list">
          {ATTRIBUTIONS.map((a) => (
            <a className="attribution-row" href={a.url} target="_blank" rel="noopener noreferrer" key={a.name}>
              <span className="attribution-name">{a.name}</span>
              <span className="attribution-desc">{a.desc}</span>
            </a>
          ))}
        </div>
      </div>
    </main>
  );
}
