import fs from "fs";
import path from "path";

interface PosterEntry {
  id: number;
  title: string;
  file: string;
}

const ROW_COUNT = 10;

function loadPosters(): PosterEntry[] {
  const manifestPath = path.join(process.cwd(), "public", "posters", "manifest.json");
  const raw = fs.readFileSync(manifestPath, "utf-8");
  return JSON.parse(raw);
}

// Splits the (deduplicated) poster pool into disjoint rows — every poster
// appears in exactly one row, so the same title is never on screen twice at
// once, no matter how the rows scroll past each other.
function splitIntoRows(posters: PosterEntry[], rowCount: number): PosterEntry[][] {
  const rows: PosterEntry[][] = Array.from({ length: rowCount }, () => []);
  posters.forEach((poster, i) => {
    rows[i % rowCount].push(poster);
  });
  return rows;
}

export function PosterMarquee() {
  const posters = loadPosters();
  const rows = splitIntoRows(posters, ROW_COUNT);

  return (
    <div className="poster-marquee" aria-hidden="true">
      {rows.map((row, i) => {
        const duration = 50 + i * 9; // seconds — every row a different speed
        const reverse = i % 2 === 1; // alternating scroll direction
        return (
          <div
            key={i}
            className={`poster-marquee-row${reverse ? " reverse" : ""}`}
            style={{ animationDuration: `${duration}s` }}
          >
            {[...row, ...row].map((poster, j) => (
              <div className="poster-marquee-cell" key={`${poster.id}-${j}`}>
                <img src={poster.file} alt="" loading="eager" />
              </div>
            ))}
          </div>
        );
      })}
    </div>
  );
}
