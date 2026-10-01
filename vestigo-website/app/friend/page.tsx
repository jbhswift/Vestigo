import { Metadata } from "next";
import { OpenInVestigoButton } from "@/components/OpenInVestigoButton";

interface PageProps {
  searchParams: Promise<{ id?: string; rid?: string; name?: string }>;
}

export async function generateMetadata({ searchParams }: PageProps): Promise<Metadata> {
  const { name } = await searchParams;
  const title = name ? `${name} wants to add you on Vestigo` : "Add me on Vestigo";
  const description = "No account needed — tap to add each other as friends automatically.";
  return {
    title,
    description,
    openGraph: { title, description },
    twitter: { card: "summary", title, description },
  };
}

export default async function FriendPage({ searchParams }: PageProps) {
  const { name } = await searchParams;
  const params = await searchParams;
  const query = new URLSearchParams(
    Object.entries(params).filter(([, v]) => v !== undefined) as [string, string][]
  ).toString();
  const deepLink = `vestigo://friend${query ? `?${query}` : ""}`;

  return (
    <main className="card-page">
      <img src="/vestigo-app-icon.png" alt="Vestigo" className="app-icon" style={{ width: 84 }} />
      <div className="glass invite-card">
        <h1>{name ? `${name} wants to add you on Vestigo` : "Add me on Vestigo"}</h1>
        <p className="sub">
          No account needed — tap below and {name ? "you'll both" : "you'll"} be added as friends
          automatically.
        </p>

        <div className="invite-actions">
          <OpenInVestigoButton deepLink={deepLink} />
          <div className="divider">or</div>
          <a
            className="btn btn-ghost btn-block"
            href="https://testflight.apple.com/join/zbvP2WEx"
            target="_blank"
            rel="noopener noreferrer"
          >
            Get Vestigo on TestFlight
          </a>
        </div>
      </div>
    </main>
  );
}
