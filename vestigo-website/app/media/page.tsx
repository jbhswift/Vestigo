import { Metadata } from "next";
import { fetchTMDbDetail, posterURL, TMDbItem, TMDbProvider, TMDbVideo } from "@/lib/tmdb";
import { OpenInVestigoButton } from "@/components/OpenInVestigoButton";
import { MediaCard } from "@/components/MediaCard";

interface PageProps {
  searchParams: Promise<{ id?: string; kind?: string }>;
}

function resolveKind(kindParam?: string): "movie" | "tv" {
  return kindParam === "tv" ? "tv" : "movie";
}

async function loadDetail(id: string, kind: "movie" | "tv"): Promise<TMDbItem> {
  const append =
    kind === "movie"
      ? "credits,videos,similar,recommendations,external_ids,release_dates,watch/providers"
      : "credits,videos,similar,recommendations,external_ids,content_ratings,watch/providers";
  return fetchTMDbDetail(kind, id, append);
}

function pickTrailer(videos?: { results?: TMDbVideo[] }) {
  const results = videos?.results ?? [];
  const trailers = results.filter((v) => v.site === "YouTube" && v.type === "Trailer");
  return trailers.find((v) => v.official) ?? trailers[0] ?? results.find((v) => v.site === "YouTube") ?? null;
}

function dedupeProviders(providers: TMDbProvider[]) {
  const seen = new Set<number>();
  return providers.filter((p) => {
    if (seen.has(p.provider_id)) return false;
    seen.add(p.provider_id);
    return true;
  });
}

export async function generateMetadata({ searchParams }: PageProps): Promise<Metadata> {
  const { id, kind: kindParam } = await searchParams;
  const kind = resolveKind(kindParam);
  if (!id || !/^\d+$/.test(id)) return { title: "Vestigo" };

  try {
    const data = await loadDetail(id, kind);
    const title = data.title ?? data.name ?? "Vestigo";
    const poster = posterURL(data.poster_path, "w342");
    return {
      title,
      description: data.overview || undefined,
      openGraph: {
        title,
        description: data.overview || undefined,
        images: poster ? [{ url: poster, width: 342, height: 513 }] : undefined,
      },
      twitter: {
        card: "summary_large_image",
        title,
        description: data.overview || undefined,
        images: poster ? [poster] : undefined,
      },
    };
  } catch {
    return { title: "Vestigo" };
  }
}

export default async function MediaPage({ searchParams }: PageProps) {
  const { id, kind: kindParam } = await searchParams;
  const kind = resolveKind(kindParam);
  const deepLink = `vestigo://media?id=${id ?? ""}&kind=${kind}`;

  if (!id || !/^\d+$/.test(id)) {
    return (
      <main className="wrap detail-page">
        <div className="open-app-bar">
          <OpenInVestigoButton deepLink={deepLink} />
        </div>
        <h1>Vestigo</h1>
      </main>
    );
  }

  let data: TMDbItem;
  try {
    data = await loadDetail(id, kind);
  } catch {
    return (
      <main className="wrap detail-page">
        <div className="open-app-bar">
          <OpenInVestigoButton deepLink={deepLink} />
        </div>
        <h1>Check this out on Vestigo</h1>
      </main>
    );
  }

  const title = data.title ?? data.name ?? "Untitled";
  const releaseDate = data.release_date ?? data.first_air_date ?? "";
  const year = releaseDate ? releaseDate.slice(0, 4) : null;
  const runtime =
    kind === "movie"
      ? data.runtime
        ? `${data.runtime} min`
        : null
      : data.number_of_seasons
        ? `${data.number_of_seasons} season${data.number_of_seasons === 1 ? "" : "s"}`
        : null;
  const genres = (data.genres ?? []).slice(0, 3).map((g) => g.name);
  const rating =
    typeof data.vote_average === "number" && data.vote_average > 0
      ? `★ ${data.vote_average.toFixed(1)}`
      : null;
  const poster = posterURL(data.poster_path, "w342");
  const imdbID = data.external_ids?.imdb_id;
  const cast = (data.credits?.cast ?? []).slice(0, 15);
  const trailer = pickTrailer(data.videos);

  const region = "US";
  const regionProviders = data["watch/providers"]?.results?.[region];
  const providers = regionProviders
    ? dedupeProviders([
        ...(regionProviders.flatrate ?? []),
        ...(regionProviders.free ?? []),
        ...(regionProviders.ads ?? []),
      ])
    : [];

  const seenSimilar = new Set<number>();
  const similar = [...(data.recommendations?.results ?? []), ...(data.similar?.results ?? [])]
    .filter((item) => {
      if (seenSimilar.has(item.id)) return false;
      seenSimilar.add(item.id);
      return true;
    })
    .slice(0, 12);

  return (
    <main className="wrap detail-page">
      <div className="open-app-bar">
        <OpenInVestigoButton deepLink={deepLink} />
      </div>

      <div className="detail-header">
        <div className="detail-poster">{poster && <img src={poster} alt={title} />}</div>
        <div className="detail-info">
          <h1>{title}</h1>
          <div className="detail-meta">
            {[kind === "tv" ? "TV Series" : "Movie", year, runtime, ...genres, rating]
              .filter(Boolean)
              .join(" · ")}
          </div>
        </div>
      </div>

      {data.overview && <p className="detail-overview">{data.overview}</p>}
      {imdbID && (
        <a className="imdb-link" href={`https://www.imdb.com/title/${imdbID}/`} target="_blank" rel="noopener noreferrer">
          View on IMDb →
        </a>
      )}

      {cast.length > 0 && (
        <div className="feature-group">
          <h2>Cast</h2>
          <div className="media-row">
            {cast.map((person) => (
              <div className="cast-card" key={person.id}>
                <div className="cast-photo">
                  {person.profile_path && <img src={posterURL(person.profile_path)!} alt="" loading="lazy" />}
                </div>
                <div className="cast-name">{person.name}</div>
                <div className="cast-role">{person.character}</div>
              </div>
            ))}
          </div>
        </div>
      )}

      {trailer && (
        <div className="feature-group">
          <h2>Trailer</h2>
          <div className="trailer-wrap">
            <iframe
              src={`https://www.youtube-nocookie.com/embed/${trailer.key}`}
              title="Trailer"
              allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
              allowFullScreen
              loading="lazy"
            />
          </div>
        </div>
      )}

      {providers.length > 0 && (
        <div className="feature-group">
          <h2>Where to watch</h2>
          <div className="provider-list glass">
            {providers.map((p) => (
              <div className="provider-row" key={p.provider_id}>
                <div className="provider-logo">
                  {p.logo_path && <img src={posterURL(p.logo_path)!} alt="" loading="lazy" />}
                </div>
                <div>
                  <div className="provider-name">{p.provider_name}</div>
                  <div className="provider-type">Streaming in {region}</div>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}

      {similar.length > 0 && (
        <div className="feature-group">
          <h2>More like this</h2>
          <div className="media-row">
            {similar.map((item) => (
              <MediaCard key={item.id} item={item} fallbackKind={kind} />
            ))}
          </div>
        </div>
      )}
    </main>
  );
}
