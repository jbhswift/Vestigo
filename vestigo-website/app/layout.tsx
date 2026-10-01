import type { Metadata, Viewport } from "next";
import { Nav } from "@/components/Nav";
import "./globals.css";

export const metadata: Metadata = {
  metadataBase: new URL("https://vestigo-app.com"),
  title: {
    default: "Vestigo — Track what you watch",
    template: "%s — Vestigo",
  },
  description:
    "Vestigo is a personal movie and TV tracker for iOS. Discover what to watch next, track what you've seen, and get recommendations that reflect your history.",
  icons: { icon: "/vestigo-app-icon.png" },
};

export const viewport: Viewport = {
  width: "device-width",
  initialScale: 0.85,
  maximumScale: 5,
  themeColor: "#000000",
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>
        <Nav />
        {children}
      </body>
    </html>
  );
}
