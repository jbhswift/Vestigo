import { TMDbItem, posterURL } from "@/lib/tmdb";

export function MediaCard({
  item,
  fallbackKind,
}: {
  item: TMDbItem;
  fallbackKind: "movie" | "tv";
}) {
  const kind = item.media_type === "tv" ? "tv" : item.media_type === "movie" ? "movie" : fallbackKind;
  const title = item.title ?? item.name ?? "Untitled";
  const date = item.release_date ?? item.first_air_date ?? "";
  const year = date ? date.slice(0, 4) : "";
  const rating =
    typeof item.vote_average === "number" && item.vote_average > 0
      ? item.vote_average.toFixed(1)
      : null;
  const poster = posterURL(item.poster_path);

  return (
    <a className="media-card" href={`/media?id=${item.id}&kind=${kind}`}>
      <div className="media-card-poster">
        {poster && <img src={poster} alt="" loading="lazy" />}
      </div>
      <div className="media-card-title">{title}</div>
      <div className="media-card-meta">
        {[year, rating ? `★ ${rating}` : null].filter(Boolean).join(" · ")}
      </div>
    </a>
  );
}
