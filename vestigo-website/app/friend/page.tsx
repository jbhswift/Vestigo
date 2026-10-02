import { Metadata } from "next";
import { OpenInVestigoButton } from "@/components/OpenInVestigoButton";
import { Nav } from "@/components/Nav";

// Reached via ?t=<opaque invite token> — see VestigoBackend/supabase/migrations/002_friends_system.sql
// (create_invite/get_invite_preview) and ContentView.swift's onOpenURL/onContinueUserActivity, which
// expect exactly this shape. Deliberately does NOT personalize this page with an inviter name: unlike
// the native app (which calls get_invite_preview — an authenticated RPC — to get a server-verified
// name), a web visitor has no Supabase session, so there is no way to verify a name here. Showing one
// anyway would mean trusting an arbitrary client-supplied URL param, exactly the spoofable pattern the
// Supabase-backed redesign was built to eliminate. The real, verified name is shown once the person is
// actually in the app and signed in.
interface PageProps {
  searchParams: Promise<{ t?: string }>;
}

export async function generateMetadata(): Promise<Metadata> {
  const title = "Add me on Vestigo";
  const description = "Open the invite in Vestigo to see who sent it and add them as a friend.";
  return {
    title,
    description,
    openGraph: { title, description },
    twitter: { card: "summary", title, description },
  };
}

export default async function FriendPage({ searchParams }: PageProps) {
  const { t } = await searchParams;
  const deepLink = `vestigo://friend${t ? `?t=${encodeURIComponent(t)}` : ""}`;

  return (
    <>
      <Nav />
      <main className="card-page has-nav-offset">
        <img src="/vestigo-app-icon.png" alt="Vestigo" className="app-icon" style={{ width: 84 }} />
        <div className="glass invite-card">
          <h1>Add me on Vestigo</h1>
          <p className="sub">
            Open this invite in Vestigo to see who sent it, then confirm to add each other as friends.
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
    </>
  );
}
