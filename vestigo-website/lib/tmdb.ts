// Same public, no-auth TMDb proxy the iOS app itself calls (VestigoBackendClient).
// Server components call it directly (no CORS concerns server-side); the
// client-side search bar calls it too, since the proxy sends
// Access-Control-Allow-Origin: * for exactly this reason.
export const TMDB_BACKEND = "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api";
export const TESTFLIGHT_URL = "https://testflight.apple.com/join/zbvP2WEx";

export interface TMDbItem {
  id: number;
  title?: string;
  name?: string;
  poster_path?: string | null;
  backdrop_path?: string | null;
  release_date?: string;
  first_air_date?: string;
  vote_average?: number;
  media_type?: string;
  overview?: string;
  genres?: { id: number; name: string }[];
  runtime?: number;
  number_of_seasons?: number;
  credits?: { cast?: TMDbCastMember[] };
  videos?: { results?: TMDbVideo[] };
  similar?: { results?: TMDbItem[] };
  recommendations?: { results?: TMDbItem[] };
  external_ids?: { imdb_id?: string | null };
  "watch/providers"?: { results?: Record<string, TMDbWatchProviderRegion> };
}

export interface TMDbCastMember {
  id: number;
  name: string;
  character?: string;
  profile_path?: string | null;
}

export interface TMDbVideo {
  id: string;
  key: string;
  site: string;
  type: string;
  official?: boolean;
}

export interface TMDbProvider {
  provider_id: number;
  provider_name: string;
  logo_path?: string | null;
}

export interface TMDbWatchProviderRegion {
  link?: string;
  flatrate?: TMDbProvider[];
  free?: TMDbProvider[];
  ads?: TMDbProvider[];
}

interface TMDbListResponse {
  results?: TMDbItem[];
}

export async function fetchTMDbList(
  path: string,
  extraParams: Record<string, string> = {}
): Promise<TMDbItem[]> {
  const params = new URLSearchParams({ path, ...extraParams });
  const res = await fetch(`${TMDB_BACKEND}/tmdb-proxy?${params.toString()}`, {
    next: { revalidate: 3600 },
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  const data: TMDbListResponse = await res.json();
  return data.results ?? [];
}

export async function fetchTMDbDetail(
  kind: "movie" | "tv",
  id: string,
  append: string
): Promise<TMDbItem> {
  const params = new URLSearchParams({ path: `/${kind}/${id}`, append_to_response: append });
  const res = await fetch(`${TMDB_BACKEND}/tmdb-proxy?${params.toString()}`, {
    next: { revalidate: 3600 },
  });
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.json();
}

export function posterURL(path: string | null | undefined, size: "w185" | "w342" = "w185") {
  return path ? `https://image.tmdb.org/t/p/${size}${path}` : null;
}
