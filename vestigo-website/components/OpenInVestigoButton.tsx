"use client";

import { TESTFLIGHT_URL } from "@/lib/tmdb";

// Only ever fires on a tap — visiting a shared link should never force-launch
// the app on its own. Tries the vestigo:// custom scheme; if the app opens,
// this tab backgrounds (blur/pagehide) and the fallback timer is cancelled.
// If nothing happens for ~1.5s, assume the app isn't installed and go to
// TestFlight instead.
export function OpenInVestigoButton({
  deepLink,
  label = "Open in Vestigo",
  className = "btn btn-primary btn-block",
}: {
  deepLink: string;
  label?: string;
  className?: string;
}) {
  function handleClick() {
    let fallbackFired = false;
    const cancel = () => {
      fallbackFired = true;
    };
    window.addEventListener("blur", cancel, { once: true });
    window.addEventListener("pagehide", cancel, { once: true });

    window.location.href = deepLink;

    setTimeout(() => {
      if (!fallbackFired) window.location.href = TESTFLIGHT_URL;
    }, 1500);
  }

  return (
    <button className={className} onClick={handleClick}>
      {label}
    </button>
  );
}
