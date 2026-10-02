import { PosterMarquee } from "@/components/PosterMarquee";

export default function DownloadPage() {
  return (
    <>
      <PosterMarquee />
      <main className="download-hero">
        <img src="/vestigo-app-icon.png" alt="Vestigo app icon" className="app-icon" />
        <h1>Vestigo</h1>
        <a
          className="btn btn-primary"
          href="https://testflight.apple.com/join/zbvP2WEx"
          target="_blank"
          rel="noopener noreferrer"
        >
          Download on TestFlight
        </a>
      </main>
    </>
  );
}
