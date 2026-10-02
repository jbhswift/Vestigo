import { fetchTMDbList } from "@/lib/tmdb";
import { HomeContent } from "@/components/HomeContent";

export default async function HomePage() {
  const [trendingRaw, newReleases, upcoming] = await Promise.all([
    fetchTMDbList("/trending/all/week").catch(() => []),
    fetchTMDbList("/movie/now_playing", { region: "US" }).catch(() => []),
    fetchTMDbList("/movie/upcoming", { region: "US" }).catch(() => []),
  ]);
  const trending = trendingRaw.filter((item) => item.media_type !== "person");

  return (
    <main className="wrap" style={{ paddingBottom: 40 }}>
      <HomeContent trending={trending} newReleases={newReleases} upcoming={upcoming} />
    </main>
  );
}
