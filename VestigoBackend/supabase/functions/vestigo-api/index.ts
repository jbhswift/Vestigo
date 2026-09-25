// Fire-and-forget PostHog tracking for backend API calls
function trackApiCall(service: string): void {
  const apiKey = Deno.env.get("POSTHOG_API_KEY")
  if (!apiKey) return
  fetch("https://us.posthog.com/capture/", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      api_key: apiKey,
      event: "backend_api_call",
      properties: { service, distinct_id: "backend", source: "supabase" },
      timestamp: new Date().toISOString(),
    }),
  }).catch(() => {})
}

function normalizeAMCFormat(raw: string | null): string | null {
  if (!raw) return null
  // Strip all non-alphanumeric chars so "Laser at AMC", "LaserAtAMC", "LASERATAMC" all match
  const s = raw.toLowerCase().replace(/[^a-z0-9]/g, "")
  if (s.includes("imax")) return "IMAX"
  if (s.includes("dolby")) return "Dolby Cinema"
  if (s.includes("plf") || s.includes("premiumlarge") || s.includes("premiumformat")) return "PLF"
  if (s.includes("laser")) return "Laser at AMC"
  if (s.includes("3d")) return "3D"
  if (s.includes("dine") || s.includes("fork")) return "Dine-In"
  if (s.includes("bigd")) return "BigD"
  if (s.includes("prime")) return "Prime at AMC"
  // Standard/digital/unknown codes are not worth showing to users
  return null
}

function normalizeTitle(value: string) {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
}

function matchScore(name: string, query: string) {
  const normalizedName = normalizeTitle(name)
  const normalizedQuery = normalizeTitle(query)

  if (normalizedName === normalizedQuery) return 100
  if (normalizedName.includes(normalizedQuery)) return 75
  if (normalizedQuery.includes(normalizedName)) return 60
  return 0
}

function previewSecret(name: string) {
  const value = Deno.env.get(name)

  return {
    exists: Boolean(value)
  }
}

async function fetchWithTimeout(url: URL | string, init: RequestInit = {}, timeoutMilliseconds = 8000) {
  const controller = new AbortController()
  const timeout = setTimeout(() => controller.abort(), timeoutMilliseconds)

  try {
    return await fetch(url, {
      ...init,
      signal: controller.signal
    })
  } finally {
    clearTimeout(timeout)
  }
}

function tmdbVoteAverage(result: any) {
  return typeof result?.vote_average === "number" ? result.vote_average : 0
}

function itemTitle(result: any, kind: "movie" | "tv") {
  return kind === "movie"
    ? result.title ?? result.original_title ?? "Untitled"
    : result.name ?? result.original_name ?? "Untitled"
}

function itemReleaseDate(result: any, kind: "movie" | "tv") {
  return kind === "movie"
    ? result.release_date ?? null
    : result.first_air_date ?? null
}

function releaseYear(value: unknown) {
  if (typeof value !== "string" || value.length < 4) return null
  const year = Number(value.slice(0, 4))
  return Number.isFinite(year) && year > 0 ? String(year) : null
}

function tmdbMovieDTO(result: any) {
  const title = itemTitle(result, "movie")

  return {
    id: result.id,
    kind: "movie",
    title,
    overview: result.overview ?? "",
    posterPath: result.poster_path ?? null,
    backdropPath: result.backdrop_path ?? null,
    releaseDate: itemReleaseDate(result, "movie"),
    voteAverage: tmdbVoteAverage(result),
    genreIDs: Array.isArray(result.genre_ids) ? result.genre_ids : [],
    originalLanguage: result.original_language ?? null
  }
}

function tmdbTVDTO(result: any) {
  const title = itemTitle(result, "tv")

  return {
    id: result.id,
    kind: "tv",
    title,
    overview: result.overview ?? "",
    posterPath: result.poster_path ?? null,
    backdropPath: result.backdrop_path ?? null,
    releaseDate: itemReleaseDate(result, "tv"),
    voteAverage: tmdbVoteAverage(result),
    genreIDs: Array.isArray(result.genre_ids) ? result.genre_ids : [],
    originalLanguage: result.original_language ?? null
  }
}

async function fetchTMDb(path: string, params: Record<string, string> = {}) {
  const tmdbKey = Deno.env.get("TMDB_API_KEY")

  if (!tmdbKey) {
    throw new Error("Missing TMDB_API_KEY")
  }

  const url = new URL(`https://api.themoviedb.org/3${path}`)
  url.searchParams.set("api_key", tmdbKey)
  url.searchParams.set("language", "en-US")

  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value)
  }

  const response = await fetchWithTimeout(url)

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`TMDb request failed: ${response.status} ${text}`)
  }

  trackApiCall("tmdb")
  incrementServiceCall("tmdb")
  return await response.json()
}

function isAllowedTMDbProxyPath(path: string) {
  if (!path.startsWith("/")) return false
  if (path.includes("..")) return false

  return [
    /^\/trending\/(all|movie|tv)\/(day|week)$/,
    /^\/movie\/(popular|now_playing|upcoming)$/,
    /^\/tv\/(popular|on_the_air|airing_today)$/,
    /^\/search\/(multi|movie|tv|person)$/,
    /^\/discover\/(movie|tv)$/,
    /^\/movie\/\d+\/(recommendations|similar|external_ids|release_dates|keywords)$/,
    /^\/tv\/\d+\/(recommendations|similar|external_ids|content_ratings|keywords)$/,
    /^\/movie\/\d+$/,
    /^\/tv\/\d+$/,
    /^\/tv\/\d+\/season\/\d+$/,
    /^\/person\/\d+$/,
    /^\/person\/\d+\/combined_credits$/
  ].some((pattern) => pattern.test(path))
}

async function tmdbProxy(path: string, params: URLSearchParams) {
  if (!isAllowedTMDbProxyPath(path)) {
    throw new Error("TMDb proxy path is not allowed")
  }

  const forwardedParams: Record<string, string> = {}
  const blockedParams = new Set(["api_key", "path"])

  for (const [key, value] of params.entries()) {
    if (!blockedParams.has(key)) {
      forwardedParams[key] = value
    }
  }

  return await fetchTMDb(path, forwardedParams)
}

async function tasteDiveSimilar(query: string, type: string, limit: string) {
  const tasteDiveKey = Deno.env.get("TASTEDIVE_API_KEY")

  if (!tasteDiveKey) {
    throw new Error("Missing TASTEDIVE_API_KEY")
  }

  const normalizedType = type === "show" ? "show" : "movie"
  const url = new URL("https://tastedive.com/api/similar")
  url.searchParams.set("q", query)
  url.searchParams.set("type", normalizedType)
  url.searchParams.set("limit", limit)
  url.searchParams.set("k", tasteDiveKey)

  const response = await fetchWithTimeout(url)

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`TasteDive request failed: ${response.status} ${text}`)
  }

  const data = await response.json()
  const results = Array.isArray(data?.Similar?.Results) ? data.Similar.Results : []

  return results
    .filter((result: any) => result?.Type === normalizedType)
    .map((result: any) => String(result?.Name ?? "").trim())
    .filter((name: string) => name.length > 0)
}

async function fetchOMDb(params: Record<string, string>, userKeys: string[]) {
  const keys = userKeys
    .map((k, i) => ({ key: k.trim(), label: i === 0 ? "user" : "vestigo-backend" }))
    .filter(a => a.key.length > 0)

  if (keys.length === 0) {
    return null
  }

  let rateLimitError: string | null = null

  for (const attempt of keys) {
    const url = new URL("https://www.omdbapi.com/")
    url.searchParams.set("apikey", attempt.key)

    for (const [key, value] of Object.entries(params)) {
      if (value.trim().length > 0) {
        url.searchParams.set(key, value)
      }
    }

    const response = await fetchWithTimeout(url)

    if (!response.ok) {
      const text = await response.text()
      const loweredText = text.toLowerCase()

      if (loweredText.includes("request limit reached")) {
        rateLimitError = `OMDb request limit reached for ${attempt.label}`
        continue
      }

      throw new Error(`OMDb request failed for ${attempt.label}: ${response.status} ${text}`)
    }

    const data = await response.json()
    const errorText = String(data?.Error ?? "")

    if (data?.Response === "False" && errorText.toLowerCase().includes("request limit reached")) {
      rateLimitError = `OMDb request limit reached for ${attempt.label}`
      continue
    }

    if (data?.Response === "False") return null

    return data
  }

  throw new Error(rateLimitError ?? "No valid OMDb key provided")
}

function parseOMDbNumber(value: unknown) {
  if (typeof value !== "string" || value === "N/A") return null
  const parsed = Number(value.replace(/,/g, ""))
  return Number.isFinite(parsed) ? parsed : null
}

function parseRottenTomatoes(value: unknown) {
  if (typeof value !== "string" || value === "N/A") return null
  const parsed = Number(value.replace("%", ""))
  return Number.isFinite(parsed) ? parsed : null
}

function normalizeOMDbRatings(data: any) {
  if (!data) return null

  const rottenTomatoesText = Array.isArray(data.Ratings)
    ? data.Ratings.find((rating: any) => rating?.Source === "Rotten Tomatoes")?.Value ?? null
    : null

  return {
    imdbID: typeof data.imdbID === "string" && data.imdbID !== "N/A" ? data.imdbID : null,
    imdbRating: parseOMDbNumber(data.imdbRating),
    imdbVotes: typeof data.imdbVotes === "string" && data.imdbVotes !== "N/A" ? data.imdbVotes : null,
    rottenTomatoesRating: parseRottenTomatoes(rottenTomatoesText),
    rottenTomatoesText
  }
}

async function omdbRatingsForTMDbID(tmdbID: number, kind: "movie" | "tv", title: string | null, year: string | null = null, userKeys: string[] = []) {
  if (userKeys.filter(k => k.trim().length > 0).length === 0) return null

  let imdbID: string | null = null

  try {
    const externalIDs = await fetchTMDb(`/${kind}/${tmdbID}/external_ids`)
    const rawIMDbID = String(externalIDs?.imdb_id ?? "").trim()
    imdbID = rawIMDbID.length > 0 ? rawIMDbID : null
  } catch {
    imdbID = null
  }

  if (imdbID) {
    const data = await fetchOMDb({ i: imdbID, plot: "short" }, userKeys)
    const ratings = normalizeOMDbRatings(data)
    if (ratings?.imdbRating || ratings?.rottenTomatoesRating || ratings?.rottenTomatoesText) {
      return ratings
    }
  }

  if (title && title.trim().length > 0) {
    const baseParams = {
      t: title,
      type: kind === "movie" ? "movie" : "series",
      plot: "short"
    }

    const attempts = year
      ? [{ ...baseParams, y: year }, baseParams]
      : [baseParams]

    for (const params of attempts) {
      const data = await fetchOMDb(params, userKeys)
      const ratings = normalizeOMDbRatings(data)
      if (ratings?.imdbRating || ratings?.rottenTomatoesRating || ratings?.rottenTomatoesText) {
        return ratings
      }
    }
  }

  return null
}

// --- Watchmode helper functions ---
async function fetchWatchmode(path: string, params: Record<string, string> = {}) {
  const watchmodeKey = Deno.env.get("WATCHMODE_API_KEY")

  if (!watchmodeKey) {
    throw new Error("Missing WATCHMODE_API_KEY")
  }

  const url = new URL(`https://api.watchmode.com/v1${path}`)
  url.searchParams.set("apiKey", watchmodeKey)

  for (const [key, value] of Object.entries(params)) {
    url.searchParams.set(key, value)
  }

  const response = await fetch(url)

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`Watchmode request failed: ${response.status} ${text}`)
  }

  trackApiCall("watchmode")
  incrementServiceCall("watchmode")
  return await response.json()
}

function normalizeWatchmodeSource(source: any) {
  const type = String(source.type ?? "").toLowerCase()
  const format = String(source.format ?? "").toUpperCase()
  const price = source.price
  const rawWebURL = source.web_url ?? source.webUrl ?? null
  const rawIOSURL = source.ios_url ?? source.iosUrl ?? null
  const webURL = typeof rawWebURL === "string" && rawWebURL.startsWith("http") ? rawWebURL : null
  const iosURL = typeof rawIOSURL === "string" && !rawIOSURL.toLowerCase().includes("deeplinks available for paid plans only") ? rawIOSURL : null

  let typeText = "Watch"
  if (type === "sub" || type === "subscription") typeText = "Subscription"
  if (type === "free") typeText = "Free"
  if (type === "rent") typeText = "Rent"
  if (type === "buy" || type === "purchase") typeText = "Buy"

  let priceText: string | null = null
  if (typeText === "Subscription") {
    priceText = "Included"
  } else if (typeText === "Free") {
    priceText = "Free"
  } else if (typeof price === "number") {
    priceText = `$${price.toFixed(2)}`
  }

  return {
    serviceName: source.name ?? source.source_name ?? source.sourceName ?? "Unknown service",
    type: typeText,
    priceText,
    qualityText: format.length > 0 ? format : null,
    webURL,
    iosURL,
    openURL: iosURL ?? webURL
  }
}

function watchmodeSourceRank(source: any) {
  const type = String(source.type ?? "").toLowerCase()
  const quality = String(source.qualityText ?? "").toUpperCase()
  const priceText = String(source.priceText ?? "")
  const priceNumber = Number(priceText.replace(/[^0-9.]/g, ""))

  let typeRank = 99
  if (type === "subscription") typeRank = 0
  if (type === "free") typeRank = 1
  if (type === "rent") typeRank = 2
  if (type === "buy") typeRank = 3

  let qualityRank = 99
  if (quality === "4K") qualityRank = 0
  if (quality === "HD") qualityRank = 1
  if (quality === "SD") qualityRank = 2

  return {
    typeRank,
    priceRank: Number.isFinite(priceNumber) ? priceNumber : 0,
    qualityRank
  }
}

function dedupeWatchmodeSources(sources: any[]) {
  const bestByKey = new Map<string, any>()

  for (const source of sources) {
    const key = `${source.serviceName}-${source.type}`
    const existing = bestByKey.get(key)

    if (!existing) {
      bestByKey.set(key, source)
      continue
    }

    const currentRank = watchmodeSourceRank(source)
    const existingRank = watchmodeSourceRank(existing)

    if (currentRank.priceRank < existingRank.priceRank) {
      bestByKey.set(key, source)
      continue
    }

    if (currentRank.priceRank === existingRank.priceRank && currentRank.qualityRank < existingRank.qualityRank) {
      bestByKey.set(key, source)
    }
  }

  return Array.from(bestByKey.values()).sort((a: any, b: any) => {
    const lhs = watchmodeSourceRank(a)
    const rhs = watchmodeSourceRank(b)

    if (lhs.typeRank !== rhs.typeRank) return lhs.typeRank - rhs.typeRank
    if (lhs.priceRank !== rhs.priceRank) return lhs.priceRank - rhs.priceRank
    if (lhs.qualityRank !== rhs.qualityRank) return lhs.qualityRank - rhs.qualityRank
    return String(a.serviceName).localeCompare(String(b.serviceName))
  })
}

function watchmodeTitleIDFromSearch(data: any, kind: "movie" | "tv") {
  const titleResults = Array.isArray(data?.title_results)
    ? data.title_results
    : Array.isArray(data?.results)
      ? data.results
      : []

  const expectedTypes = kind === "movie"
    ? new Set(["movie"])
    : new Set(["tv_series", "tv_miniseries", "tv_special", "tv_movie", "tv"])

  const exactKindMatch = titleResults.find((item: any) => {
    const id = Number(item?.id)
    const type = String(item?.type ?? item?.result_type ?? "").toLowerCase()
    return Number.isFinite(id) && id > 0 && expectedTypes.has(type)
  })

  const fallbackMatch = titleResults.find((item: any) => {
    const id = Number(item?.id)
    return Number.isFinite(id) && id > 0
  })

  const match = exactKindMatch ?? fallbackMatch
  const id = Number(match?.id)

  return Number.isFinite(id) && id > 0 ? id : null
}

async function watchmodeTitleIDForTMDbID(
  tmdbID: number,
  kind: "movie" | "tv",
  clientImdbID?: string,
  title?: string,
  year?: string
) {
  const searchAttempts: Array<{ search_field: string, search_value: string }> = []

  // Use the client-supplied imdbID directly; only fall back to a TMDB round-trip if absent.
  let resolvedImdbID = clientImdbID?.trim() || null

  if (!resolvedImdbID) {
    try {
      const externalIDs = await fetchTMDb(`/${kind}/${tmdbID}/external_ids`)
      const fetched = String(externalIDs?.imdb_id ?? "").trim()
      if (fetched.length > 0) resolvedImdbID = fetched
    } catch {
      // Fall through to ID-based attempts.
    }
  }

  if (resolvedImdbID) {
    searchAttempts.push({ search_field: "imdb_id", search_value: resolvedImdbID })
  }

  searchAttempts.push(
    { search_field: kind === "movie" ? "tmdb_movie_id" : "tmdb_tv_id", search_value: String(tmdbID) },
    { search_field: "tmdb_id", search_value: String(tmdbID) }
  )

  // Title+year as final fallback so new/obscure content can still be found.
  const cleanTitle = title?.trim()
  if (cleanTitle) {
    searchAttempts.push({ search_field: "name", search_value: cleanTitle })
  }

  const expectedTypes = kind === "movie"
    ? new Set(["movie"])
    : new Set(["tv_series", "tv_miniseries", "tv_special", "tv_movie", "tv"])

  for (const attempt of searchAttempts) {
    try {
      const search = await fetchWatchmode("/search/", attempt)

      if (attempt.search_field === "name") {
        // For title searches, validate with kind and year to avoid wrong matches.
        const titleResults = Array.isArray(search?.title_results)
          ? search.title_results
          : Array.isArray(search?.results) ? search.results : []

        const yearNum = year ? Number(year) : null

        const confirmed = titleResults.find((item: any) => {
          const type = String(item?.type ?? item?.result_type ?? "").toLowerCase()
          if (!expectedTypes.has(type)) return false
          if (yearNum) {
            const rawYear = item?.year ?? item?.release_date ?? item?.first_air_date
            const itemYear = rawYear ? Number(String(rawYear).slice(0, 4)) : 0
            // Only reject on year mismatch if we actually parsed a year from the result
            if (itemYear > 0 && Math.abs(itemYear - yearNum) > 1) return false
          }
          return true
        })

        const id = Number(confirmed?.id)
        if (Number.isFinite(id) && id > 0) return id
        continue
      }

      const watchmodeID = watchmodeTitleIDFromSearch(search, kind)
      if (watchmodeID) return watchmodeID
    } catch {
      continue
    }
  }

  return null
}

async function watchmodeSourcesForTMDbID(
  tmdbID: number,
  kind: "movie" | "tv",
  country: string,
  imdbID?: string,
  title?: string,
  year?: string
) {
  const watchmodeID = await watchmodeTitleIDForTMDbID(tmdbID, kind, imdbID, title, year)

  if (!watchmodeID) {
    return []
  }

  const sources = await fetchWatchmode(`/title/${watchmodeID}/sources/`, {
    regions: country.toUpperCase()
  })

  if (!Array.isArray(sources)) {
    return []
  }

  return dedupeWatchmodeSources(
    sources
      .map(normalizeWatchmodeSource)
      .filter((source: any) => source.serviceName && (source.webURL || source.iosURL))
  )
}

async function fetchWikidataSPARQL(query: string) {
  const url = new URL("https://query.wikidata.org/sparql")
  url.searchParams.set("query", query)
  url.searchParams.set("format", "json")

  const response = await fetch(url, {
    headers: {
      "Accept": "application/sparql-results+json",
      "User-Agent": "Vestigo/1.0 franchise-recommendations"
    }
  })

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`Wikidata request failed: ${response.status} ${text}`)
  }

  incrementServiceCall("wikidata")
  return await response.json()
}

function sparqlString(value: string) {
  return value.replace(/\\/g, "\\\\").replace(/"/g, "\\\"")
}

async function searchWikidataFranchiseEntity(query: string) {
  const escapedQuery = sparqlString(query)
  const sparql = `
SELECT ?franchise ?franchiseLabel WHERE {
  ?franchise rdfs:label "${escapedQuery}"@en.
  SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
}
LIMIT 10
`

  const data = await fetchWikidataSPARQL(sparql)
  const bindings = data?.results?.bindings ?? []

  const exactMatches = bindings
    .map((binding: any) => ({
      uri: binding.franchise?.value ?? null,
      label: binding.franchiseLabel?.value ?? query
    }))
    .filter((item: any) => typeof item.uri === "string")
    .sort((a: any, b: any) => matchScore(b.label, query) - matchScore(a.label, query))

  return exactMatches[0] ?? null
}

async function getWikidataFranchiseRecommendations(query: string) {
  const franchise = await searchWikidataFranchiseEntity(query)

  if (!franchise?.uri) {
    return {
      franchise: null,
      refs: [] as Array<{ id: number, kind: "movie" | "tv" }>
    }
  }

  const escapedFranchiseURI = franchise.uri.replace(/[<>]/g, "")
    const sparql = `
    SELECT DISTINCT ?work ?workLabel ?tmdbMovieID ?tmdbTVID WHERE {
      VALUES ?franchise { <${escapedFranchiseURI}> }
      {
        ?work (wdt:P179|wdt:P361)+ ?franchise.
      }
      UNION
      {
        ?franchise (wdt:P527)+ ?work.
      }
      OPTIONAL { ?work wdt:P4947 ?tmdbMovieID. }
      OPTIONAL { ?work wdt:P4983 ?tmdbTVID. }
      FILTER(BOUND(?tmdbMovieID) || BOUND(?tmdbTVID))
      SERVICE wikibase:label { bd:serviceParam wikibase:language "en". }
    }
    LIMIT 300
    `

  const data = await fetchWikidataSPARQL(sparql)
  const bindings = data?.results?.bindings ?? []

  const refs: Array<{ id: number, kind: "movie" | "tv" }> = []

  for (const binding of bindings) {
    const movieID = Number(binding.tmdbMovieID?.value)
    const tvID = Number(binding.tmdbTVID?.value)

    if (Number.isFinite(movieID) && movieID > 0) {
      refs.push({ id: movieID, kind: "movie" })
    }

    if (Number.isFinite(tvID) && tvID > 0) {
      refs.push({ id: tvID, kind: "tv" })
    }
  }

  return {
    franchise: {
      uri: franchise.uri,
      name: franchise.label
    },
    refs: Array.from(
      new Map(refs.map((ref) => [`${ref.kind}-${ref.id}`, ref])).values()
    )
  }
}

// Search TMDb movie and TV endpoints for universe/franchise-like references by query text.
async function searchTMDbUniverseRefs(query: string) {
  const refs: Array<{ id: number, kind: "movie" | "tv" }> = []
  const normalizedQuery = normalizeTitle(query)
  const queryTokens = normalizedQuery.split(" ").filter((token) => token.length > 2)

  function matchesQueryText(item: any, titleKeys: string[]) {
    const title = titleKeys
      .map((key) => String(item?.[key] ?? ""))
      .find((value) => value.trim().length > 0) ?? ""
    const overview = String(item?.overview ?? "")
    const normalizedTitle = normalizeTitle(title)
    const normalizedText = normalizeTitle(`${title} ${overview}`)

    if (normalizedTitle.includes(normalizedQuery)) {
      return true
    }

    if (normalizedText.includes(normalizedQuery)) {
      return true
    }

    if (queryTokens.length > 1 && queryTokens.every((token) => normalizedText.includes(token))) {
      return true
    }

    return false
  }

  try {
    const movieSearch = await fetchTMDb("/search/movie", {
      query,
      include_adult: "false",
      page: "1"
    })

    const movieResults = Array.isArray(movieSearch.results) ? movieSearch.results : []

    for (const item of movieResults.slice(0, 40)) {
      if (typeof item.id === "number" && matchesQueryText(item, ["title", "original_title"])) {
        refs.push({ id: item.id, kind: "movie" })
      }
    }
  } catch {
    // Keep Wikidata results even if TMDb search fails.
  }

  try {
    const tvSearch = await fetchTMDb("/search/tv", {
      query,
      include_adult: "false",
      page: "1"
    })

    const tvResults = Array.isArray(tvSearch.results) ? tvSearch.results : []

    for (const item of tvResults.slice(0, 40)) {
      if (typeof item.id === "number" && matchesQueryText(item, ["name", "original_name"])) {
        refs.push({ id: item.id, kind: "tv" })
      }
    }
  } catch {
    // Keep Wikidata results even if TMDb search fails.
  }

  return Array.from(
    new Map(refs.map((ref) => [`${ref.kind}-${ref.id}`, ref])).values()
  )
}

async function tmdbCollectionByID(collectionID: number) {
  const collection = await fetchTMDb(`/collection/${collectionID}`)

  const parts = Array.isArray(collection.parts) ? collection.parts : []
  const items = parts
    .filter((item: any) => typeof item.id === "number")
    .map((item: any) => tmdbMovieDTO(item))

  return {
    id: collection.id,
    name: collection.name ?? "Collection",
    overview: collection.overview ?? null,
    items
  }
}

async function tmdbCollectionForMovie(movieID: number) {
  const detail = await fetchTMDb(`/movie/${movieID}`)
  const collection = detail.belongs_to_collection

  if (!collection || typeof collection.id !== "number") {
    return null
  }

  return await tmdbCollectionByID(collection.id)
}

async function getTVDBToken() {
  const tvdbKey = Deno.env.get("TVDB_API_KEY")

  if (!tvdbKey) {
    throw new Error("Missing TVDB_API_KEY")
  }

  const response = await fetch("https://api4.thetvdb.com/v4/login", {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      apikey: tvdbKey
    })
  })

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`TVDB login failed: ${response.status} ${text}`)
  }

  const json = await response.json()
  return json.data.token
}

async function fetchTVDB(path: string, token: string) {
  const response = await fetch(`https://api4.thetvdb.com/v4${path}`, {
    headers: {
      "Authorization": `Bearer ${token}`,
      "Accept": "application/json"
    }
  })

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`TVDB request failed ${path}: ${response.status} ${text}`)
  }

  trackApiCall("tvdb")
  incrementServiceCall("tvdb")
  const json = await response.json()
  return json.data
}

async function searchTVDB(query: string, token: string, type: string | null = null) {
  const url = new URL("https://api4.thetvdb.com/v4/search")
  url.searchParams.set("query", query)

  if (type) {
    url.searchParams.set("type", type)
  }

  const response = await fetch(url, {
    headers: {
      "Authorization": `Bearer ${token}`,
      "Accept": "application/json"
    }
  })

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`TVDB search failed: ${response.status} ${text}`)
  }

  const json = await response.json()
  return json.data ?? []
}

function tvdbSearchQueries(query: string) {
  const normalized = query.trim()
  const variants = [
    normalized,
    normalized.replace(/\bfranchise\b/gi, "").trim(),
    normalized.replace(/\buniverse\b/gi, "").trim(),
    normalized.replace(/\bcinematic universe\b/gi, "").trim(),
    normalized.replace(/\bcollection\b/gi, "").trim()
  ]

  return Array.from(new Set(variants.filter((item) => item.length > 0)))
}

async function searchTVDBLists(query: string, token: string) {
  const allResults: any[] = []

  for (const candidateQuery of tvdbSearchQueries(query)) {
    try {
      allResults.push(...await searchTVDB(candidateQuery, token, "list"))
    } catch {
      continue
    }
  }

  if (allResults.length === 0) {
    for (const candidateQuery of tvdbSearchQueries(query)) {
      try {
        allResults.push(...await searchTVDB(candidateQuery, token, null))
      } catch {
        continue
      }
    }
  }

  return Array.from(
    new Map(
      allResults
        .filter((item: any) => typeof item.id === "number")
        .map((item: any) => [`${item.type ?? item.recordType ?? "unknown"}-${item.id}`, item])
    ).values()
  )
}

function tvdbEntityID(entity: any) {
  const candidates = [
    entity.id,
    entity.tvdb_id,
    entity.tvdbId,
    entity.entity_id,
    entity.entityId,
    entity.seriesId,
    entity.series_id,
    entity.movieId,
    entity.movie_id
  ]

  for (const candidate of candidates) {
    const number = Number(candidate)
    if (Number.isFinite(number) && number > 0) {
      return number
    }
  }

  return null
}

function tvdbEntityKind(entity: any) {
  const raw = String(
    entity.type ??
    entity.entityType ??
    entity.entity_type ??
    entity.recordType ??
    entity.record_type ??
    entity.objectType ??
    entity.object_type ??
    ""
  ).toLowerCase()

  if (raw.includes("movie") || raw === "film") return "movie"
  if (raw.includes("series") || raw.includes("show") || raw.includes("tv")) return "tv"

  if (entity.movieName || entity.movie_name) return "movie"
  if (entity.seriesName || entity.series_name) return "tv"

  return "unknown"
}

async function getTVDBEntityExtended(entity: any, token: string) {
  const id = tvdbEntityID(entity)
  const kind = tvdbEntityKind(entity)

  if (!id) return null

  const paths =
    kind === "movie"
      ? [`/movies/${id}/extended`]
      : kind === "tv"
        ? [`/series/${id}/extended`]
        : [`/series/${id}/extended`, `/movies/${id}/extended`]

  for (const path of paths) {
    try {
      return await fetchTVDB(path, token)
    } catch {
      continue
    }
  }

  return null
}

async function findTMDbRefsByTVDBID(tvdbID: number) {
  const data = await fetchTMDb(`/find/${tvdbID}`, {
    external_source: "tvdb_id"
  })

  const movieRefs = Array.isArray(data.movie_results)
    ? data.movie_results
        .filter((item: any) => typeof item.id === "number")
        .map((item: any) => ({ id: item.id, kind: "movie" as const }))
    : []

  const tvRefs = Array.isArray(data.tv_results)
    ? data.tv_results
        .filter((item: any) => typeof item.id === "number")
        .map((item: any) => ({ id: item.id, kind: "tv" as const }))
    : []

  return [...movieRefs, ...tvRefs]
}

function extractTMDbRefs(value: any, inheritedKind: "movie" | "tv" | "unknown" = "unknown") {
  const refs: Array<{ id: number, kind: "movie" | "tv" }> = []

  function visit(node: any, kindHint: "movie" | "tv" | "unknown") {
    if (!node || typeof node !== "object") return

    if (Array.isArray(node)) {
      for (const item of node) {
        visit(item, kindHint)
      }
      return
    }

    const localKind = tvdbEntityKind(node)
    const nextKind = localKind === "unknown" ? kindHint : localKind

    const remoteArrays = [
      node.remoteIds,
      node.remote_ids,
      node.externalIds,
      node.external_ids,
      node.remoteID,
      node.remote_ids_list
    ].filter(Array.isArray)

    for (const array of remoteArrays) {
      for (const remote of array) {
        const source = String(
          remote.sourceName ??
          remote.source_name ??
          remote.sourceType ??
          remote.source_type ??
          remote.source ??
          remote.type ??
          remote.name ??
          ""
        ).toLowerCase()

        const rawID = String(
          remote.id ??
          remote.remoteId ??
          remote.remote_id ??
          remote.value ??
          remote.externalId ??
          remote.external_id ??
          ""
        )

        if (!source.includes("tmdb") && !source.includes("themoviedb")) {
          continue
        }

        const numericID = Number(rawID)
        if (!Number.isFinite(numericID) || numericID <= 0) {
          continue
        }

        let kind: "movie" | "tv" | null = null
        if (source.includes("tv") || source.includes("series")) {
          kind = "tv"
        } else if (source.includes("movie") || source.includes("film")) {
          kind = "movie"
        } else if (nextKind === "movie" || nextKind === "tv") {
          kind = nextKind
        }

        if (kind) {
          refs.push({ id: numericID, kind })
        }
      }
    }

    for (const child of Object.values(node)) {
      visit(child, nextKind)
    }
  }

  visit(value, inheritedKind)

  return Array.from(
    new Map(refs.map((ref) => [`${ref.kind}-${ref.id}`, ref])).values()
  )
}

async function getTVDBFranchise(query: string, includeEntityDetails = false) {
  const token = await getTVDBToken()
  const lists = await searchTVDBLists(query, token)

  const bestList = lists
    .filter((item: any) => typeof item.id === "number" && typeof (item.name ?? item.title ?? item.translations?.eng) === "string")
    .sort((a: any, b: any) => {
      const aName = String(a.name ?? a.title ?? a.translations?.eng ?? "")
      const bName = String(b.name ?? b.title ?? b.translations?.eng ?? "")
      return matchScore(bName, query) - matchScore(aName, query)
    })[0]

  if (!bestList) {
    return null
  }

  const extended = await fetchTVDB(`/lists/${bestList.id}/extended`, token)
  const entities = Array.isArray(extended.entities) ? extended.entities : []

  const entityDetails: any[] = []

  if (includeEntityDetails) {
    for (const entity of entities.slice(0, 80)) {
      const detail = await getTVDBEntityExtended(entity, token)
      if (detail) {
        entityDetails.push(detail)
      }
    }
  }

  const allTitles = entities
    .flatMap((entity: any) => [
      entity.name,
      entity.title,
      entity.seriesName,
      entity.series_name,
      entity.movieName,
      entity.movie_name
    ])
    .filter((title: unknown): title is string => typeof title === "string")
    .filter((title: string) => title.trim().length > 0)

  return {
    id: bestList.id,
    name: extended.name ?? (bestList.name ?? bestList.title ?? bestList.translations?.eng) ?? query,
    overview: extended.overview ?? bestList.overview ?? null,
    memberTitles: Array.from(new Set(allTitles.map(normalizeTitle))),
    rawTitles: Array.from(new Set(allTitles)),
    entities,
    entityDetails
  }
}

function todayUTC(): string {
  return new Date().toISOString().slice(0, 10)
}

async function incrementAIUsage() {
  try {
    const kv = await Deno.openKv()
    await kv.atomic().sum(["ai_calls", todayUTC()], 1n).commit()
  } catch {
    // Non-fatal — don't fail the request if KV is unavailable
  }
}

async function getAIUsage(date: string): Promise<number> {
  const kv = await Deno.openKv()
  const entry = await kv.get<Deno.KvU64>(["ai_calls", date])
  return Number(entry.value ?? 0n)
}

// Server-side call metering — increments a counter per service per day in Deno KV.
// This is the authoritative source for services that have no native usage API.
function incrementServiceCall(service: string): void {
  try {
    if (typeof Deno.openKv !== "function") {
      return
    }

    Deno.openKv().then(kv =>
      kv.atomic().sum(["calls", service, todayUTC()], 1n).commit()
    ).catch(() => {})
  } catch {
    // Non-fatal — don't fail the request if KV is unavailable
  }
}

const SERVICE_USAGE_KEYS = ["tmdb", "watchmode", "tvdb", "wikidata", "openrouter", "amc", "youtube", "supabase_edge"]

async function getServiceUsage(days = 30): Promise<Record<string, number>> {
  const kv = await Deno.openKv()
  const counts: Record<string, number> = {}
  const dates: string[] = []
  const now = new Date()
  for (let i = 0; i < days; i++) {
    const d = new Date(now)
    d.setUTCDate(d.getUTCDate() - i)
    dates.push(d.toISOString().slice(0, 10))
  }
  await Promise.all(SERVICE_USAGE_KEYS.map(async (svc) => {
    let total = 0
    await Promise.all(dates.map(async (date) => {
      const entry = await kv.get<Deno.KvU64>(["calls", svc, date])
      total += Number(entry.value ?? 0n)
    }))
    counts[svc] = total
  }))
  return counts
}

// --- Charts: persistent Supabase DB cache + OMDb enrichment ---

async function batchedParallel<T, R>(
  items: T[],
  batchSize: number,
  fn: (item: T) => Promise<R>
): Promise<R[]> {
  const results: R[] = []
  for (let i = 0; i < items.length; i += batchSize) {
    results.push(...(await Promise.all(items.slice(i, i + batchSize).map(fn))))
  }
  return results
}

async function getChartCache(cacheKey: string): Promise<{ items: any[], updatedAt: string } | null> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? ""
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
  if (!supabaseUrl || !supabaseKey) return null
  try {
    const resp = await fetchWithTimeout(
      `${supabaseUrl}/rest/v1/charts_cache?cache_key=eq.${encodeURIComponent(cacheKey)}&select=items,updated_at`,
      { headers: { "apikey": supabaseKey, "Authorization": `Bearer ${supabaseKey}` } }
    )
    if (!resp.ok) return null
    const rows = await resp.json()
    if (!Array.isArray(rows) || rows.length === 0) return null
    return { items: rows[0].items, updatedAt: rows[0].updated_at }
  } catch {
    return null
  }
}

async function setChartCache(cacheKey: string, items: any[]): Promise<void> {
  const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? ""
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
  if (!supabaseUrl || !supabaseKey) return
  try {
    await fetchWithTimeout(
      `${supabaseUrl}/rest/v1/charts_cache`,
      {
        method: "POST",
        headers: {
          "apikey": supabaseKey,
          "Authorization": `Bearer ${supabaseKey}`,
          "Content-Type": "application/json",
          "Prefer": "resolution=merge-duplicates"
        },
        body: JSON.stringify({ cache_key: cacheKey, items, updated_at: new Date().toISOString() })
      }
    )
  } catch { /* non-fatal */ }
}

function isCacheFresh(updatedAt: string): boolean {
  const updated = new Date(updatedAt)
  const now = new Date()
  if (now.getTime() - updated.getTime() > 7 * 24 * 60 * 60 * 1000) return false
  // Also stale if a Sunday midnight UTC has passed since the last update
  const lastSunday = new Date(now)
  lastSunday.setUTCDate(now.getUTCDate() - now.getUTCDay())
  lastSunday.setUTCHours(0, 0, 0, 0)
  return updated >= lastSunday
}

async function enrichPoolWithRatings(kind: "movie" | "tv", dtos: any[]): Promise<any[]> {
  const omdbKey = (Deno.env.get("OMDB_KEY") ?? "").trim()

  // Fetch TMDb external_ids in batches of 40 to get IMDb IDs
  const extResults = await batchedParallel(dtos, 40, async (dto) => {
    try {
      const ext = await fetchTMDb(`/${kind}/${dto.id}/external_ids`)
      const rawID = String(ext?.imdb_id ?? "").trim()
      return { id: dto.id as number, imdbID: rawID || null }
    } catch {
      return { id: dto.id as number, imdbID: null }
    }
  })

  const imdbIDMap = new Map<number, string | null>(extResults.map(e => [e.id, e.imdbID]))
  const ratingsMap = new Map<number, ReturnType<typeof normalizeOMDbRatings>>()

  if (omdbKey) {
    const withIMDbID = dtos.filter(dto => imdbIDMap.get(dto.id))
    await batchedParallel(withIMDbID, 20, async (dto) => {
      const imdbID = imdbIDMap.get(dto.id)!
      try {
        const data = await fetchOMDb({ i: imdbID, plot: "short" }, [omdbKey])
        const normalized = normalizeOMDbRatings(data)
        if (normalized) ratingsMap.set(dto.id, normalized)
      } catch {}
    })
  }

  return dtos.map(dto => ({
    ...dto,
    imdbID: imdbIDMap.get(dto.id) ?? null,
    imdbRating: ratingsMap.get(dto.id)?.imdbRating ?? null,
    imdbVotes: ratingsMap.get(dto.id)?.imdbVotes ?? null,
    rottenTomatoesRating: ratingsMap.get(dto.id)?.rottenTomatoesRating ?? null,
    rottenTomatoesText: ratingsMap.get(dto.id)?.rottenTomatoesText ?? null,
  }))
}

Deno.serve(async (req) => {
  const url = new URL(req.url)

  // Count every invocation — each request to this function = 1 Supabase Edge invocation
  incrementServiceCall("supabase_edge")

  try {
    if (url.pathname.endsWith("/ai-usage")) {
      const date = url.searchParams.get("date") ?? todayUTC()
      const count = await getAIUsage(date)
      return Response.json({ ok: true, date, count })
    }

    if (url.pathname.endsWith("/health")) {
      return Response.json({
        ok: true,
        app: "Vestigo",
        message: "Vestigo API is running"
      })
    }

    if (url.pathname.endsWith("/secrets-check")) {
      return Response.json({
        ok: true,
        secrets: {
          TVDB_API_KEY: previewSecret("TVDB_API_KEY"),
          TMDB_API_KEY: previewSecret("TMDB_API_KEY"),
          MOVIE_OF_THE_NIGHT_KEY: previewSecret("MOVIE_OF_THE_NIGHT_KEY"),
          WATCHMODE_API_KEY: previewSecret("WATCHMODE_API_KEY"),
          TASTEDIVE_API_KEY: previewSecret("TASTEDIVE_API_KEY"),
          AMC_API_KEY: previewSecret("AMC_API_KEY"),
          OPENROUTER_API_KEY: previewSecret("OPENROUTER_API_KEY"),
          OPENROUTER_BACKUP_KEY: previewSecret("OPENROUTER_BACKUP_KEY")
        }
      })
    }

    if (url.pathname.endsWith("/tmdb-proxy")) {
      const path = url.searchParams.get("path")

      if (!path) {
        return Response.json(
          { ok: false, error: "Missing TMDb path" },
          { status: 400 }
        )
      }

      const data = await tmdbProxy(path, url.searchParams)
      return Response.json(data)
    }

    if (url.pathname.endsWith("/tastedive-similar")) {
      const query = String(url.searchParams.get("q") ?? "").trim()
      const type = String(url.searchParams.get("type") ?? "movie").toLowerCase()
      const limit = String(url.searchParams.get("limit") ?? "20")

      if (!query) {
        return Response.json(
          { ok: false, error: "Missing TasteDive query" },
          { status: 400 }
        )
      }

      if (type !== "movie" && type !== "show") {
        return Response.json(
          { ok: false, error: "type must be movie or show" },
          { status: 400 }
        )
      }

      const results = await tasteDiveSimilar(query, type, limit)
      return Response.json({
        ok: true,
        source: "tastedive",
        query,
        type,
        results
      })
    }

    if (url.pathname.endsWith("/tmdb-collection-for-item")) {
      const id = Number(url.searchParams.get("id"))

      if (!Number.isFinite(id)) {
        return Response.json(
          { ok: false, error: "Missing or invalid movie id" },
          { status: 400 }
        )
      }

      const collection = await tmdbCollectionForMovie(id)

      return Response.json({
        ok: true,
        collection
      })
    }

    if (url.pathname.endsWith("/tmdb-collection")) {
      const id = Number(url.searchParams.get("id"))

      if (!Number.isFinite(id)) {
        return Response.json(
          { ok: false, error: "Missing or invalid collection id" },
          { status: 400 }
        )
      }

      const collection = await tmdbCollectionByID(id)

      return Response.json({
        ok: true,
        collection
      })
    }

    if (url.pathname.endsWith("/watchmode-sources")) {
      const tmdbID = Number(url.searchParams.get("tmdbID") ?? url.searchParams.get("id"))
      const rawKind = String(url.searchParams.get("kind") ?? "movie").toLowerCase()
      const country = String(url.searchParams.get("country") ?? "US").toUpperCase()
      const clientImdbID = url.searchParams.get("imdbID") ?? undefined
      const title = url.searchParams.get("title") ?? undefined
      const year = url.searchParams.get("year") ?? undefined

      if (!Number.isFinite(tmdbID) || tmdbID <= 0) {
        return Response.json(
          { ok: false, error: "Missing or invalid tmdbID" },
          { status: 400 }
        )
      }

      if (rawKind !== "movie" && rawKind !== "tv") {
        return Response.json(
          { ok: false, error: "kind must be movie or tv" },
          { status: 400 }
        )
      }

      const sources = await watchmodeSourcesForTMDbID(tmdbID, rawKind, country, clientImdbID, title, year)

      return Response.json({
        ok: true,
        source: "watchmode",
        tmdbID,
        kind: rawKind,
        country,
        count: sources.length,
        sources
      })
    }

    if (url.pathname.endsWith("/ratings")) {
      const tmdbID = Number(url.searchParams.get("tmdbID") ?? url.searchParams.get("id"))
      const rawKind = String(url.searchParams.get("kind") ?? "movie").toLowerCase()
      const title = url.searchParams.get("title")
      const year = releaseYear(url.searchParams.get("year"))
      const userKey = (url.searchParams.get("userKey") ?? "").trim()
      const backendKey = (Deno.env.get("OMDB_KEY") ?? "").trim()
      const keys = [userKey, backendKey].filter(k => k.length > 0)

      if (!Number.isFinite(tmdbID) || tmdbID <= 0) {
        return Response.json(
          { ok: false, error: "Missing or invalid tmdbID" },
          { status: 400 }
        )
      }

      if (rawKind !== "movie" && rawKind !== "tv") {
        return Response.json(
          { ok: false, error: "kind must be movie or tv" },
          { status: 400 }
        )
      }

      const ratings = await omdbRatingsForTMDbID(tmdbID, rawKind, title, year, keys)

      return Response.json({
        ok: true,
        source: "omdb",
        tmdbID,
        kind: rawKind,
        ratings
      })
    }

    if (url.pathname.endsWith("/franchise-membership")) {
      const fallbackID = url.searchParams.get("id") ?? "unknown"
      const query = url.searchParams.get("query")

      if (!query) {
        return Response.json(
          { ok: false, error: "Missing query" },
          { status: 400 }
        )
      }

      const tvdbFranchise = await getTVDBFranchise(query, false)

      if (!tvdbFranchise) {
        return Response.json({
          ok: true,
          franchise: null
        })
      }

      return Response.json({
        ok: true,
        source: "tvdb",
        fallbackID,
        franchise: {
          id: tvdbFranchise.id,
          name: tvdbFranchise.name,
          overview: tvdbFranchise.overview,
          memberTitles: tvdbFranchise.memberTitles
        }
      })
    }
      
      if (url.pathname.endsWith("/debug-tvdb-franchise")) {
        const query = url.searchParams.get("query")

        if (!query) {
          return Response.json(
            { ok: false, error: "Missing query" },
            { status: 400 }
          )
        }

        const token = await getTVDBToken()
        const lists = await searchTVDBLists(query, token)

        const bestList = lists
          .filter((item: any) => typeof item.id === "number" && typeof (item.name ?? item.title ?? item.translations?.eng) === "string")
          .sort((a: any, b: any) => {
            const aName = String(a.name ?? a.title ?? a.translations?.eng ?? "")
            const bName = String(b.name ?? b.title ?? b.translations?.eng ?? "")
            return matchScore(bName, query) - matchScore(aName, query)
          })[0]

        if (!bestList) {
          return Response.json({
            ok: true,
            searchQueries: tvdbSearchQueries(query),
            list: null,
            searchResults: lists.slice(0, 20).map((item: any) => ({
              id: item.id,
              name: item.name ?? item.title ?? item.translations?.eng,
              type: item.type ?? item.recordType ?? item.record_type ?? null,
              keys: Object.keys(item),
              raw: item
            })),
            entities: []
          })
        }

        const extended = await fetchTVDB(`/lists/${bestList.id}/extended`, token)
        const entities = Array.isArray(extended.entities) ? extended.entities : []

        return Response.json({
          ok: true,
          searchQueries: tvdbSearchQueries(query),
          list: {
            id: bestList.id,
            name: bestList.name ?? bestList.title ?? bestList.translations?.eng,
            type: bestList.type ?? bestList.recordType ?? bestList.record_type ?? null,
            overview: bestList.overview ?? null,
            raw: bestList
          },
          extendedKeys: Object.keys(extended),
          entityCount: entities.length,
          firstEntities: entities.slice(0, 10).map((entity: any) => ({
            keys: Object.keys(entity),
            raw: entity
          }))
        })
      }

      if (url.pathname.endsWith("/franchise-recommendations")) {
        const fallbackID = url.searchParams.get("id") ?? "unknown"
        const query = url.searchParams.get("query")

        if (!query) {
          return Response.json(
            { ok: false, error: "Missing query" },
            { status: 400 }
          )
        }

        const tvdbFranchise = await getTVDBFranchise(query, true)

        const entityIDs = [
          ...(tvdbFranchise?.entities ?? []),
          ...(tvdbFranchise?.entityDetails ?? [])
        ]
          .map((entity: any) => tvdbEntityID(entity))
          .filter((id: number | null): id is number => Number.isFinite(id) && id !== null)

        const refsFromEmbeddedRemoteIDs = [
          ...extractTMDbRefs(tvdbFranchise?.entities ?? []),
          ...extractTMDbRefs(tvdbFranchise?.entityDetails ?? [])
        ]

        const refsFromTMDbFind: Array<{ id: number, kind: "movie" | "tv" }> = []

        for (const tvdbID of Array.from(new Set(entityIDs)).slice(0, 80)) {
          try {
            const refs = await findTMDbRefsByTVDBID(tvdbID)
            refsFromTMDbFind.push(...refs)
          } catch {
            continue
          }
        }

        const wikidataResult = refsFromEmbeddedRemoteIDs.length === 0 && refsFromTMDbFind.length === 0
          ? await getWikidataFranchiseRecommendations(query)
          : {
              franchise: null,
              refs: [] as Array<{ id: number, kind: "movie" | "tv" }>
            }

        const tmdbSearchRefs = refsFromEmbeddedRemoteIDs.length === 0 && refsFromTMDbFind.length === 0
          ? await searchTMDbUniverseRefs(query)
          : []

        const exactRefs = Array.from(
          new Map(
            [...refsFromEmbeddedRemoteIDs, ...refsFromTMDbFind, ...wikidataResult.refs, ...tmdbSearchRefs]
              .map((ref) => [`${ref.kind}-${ref.id}`, ref])
          ).values()
        )

        const results: any[] = []

        for (const ref of exactRefs.slice(0, 80)) {
          try {
            const detail = await fetchTMDb(`/${ref.kind}/${ref.id}`)
            results.push(ref.kind === "tv" ? tmdbTVDTO(detail) : tmdbMovieDTO(detail))
          } catch {
            continue
          }
        }

        const uniqueResults = Array.from(
          new Map(results.map((item) => [`${item.kind}-${item.id}`, item])).values()
        ).sort((a: any, b: any) => b.voteAverage - a.voteAverage)

        return Response.json({
          ok: true,
        source: wikidataResult.refs.length > 0 ? "wikidata-linked-franchise-to-tmdb" : "tvdb-id-to-tmdb-find",
          fallbackID,
          tvdbEntityIDCount: Array.from(new Set(entityIDs)).length,
          embeddedExactRefCount: refsFromEmbeddedRemoteIDs.length,
          tmdbFindRefCount: refsFromTMDbFind.length,
          wikidataFranchise: wikidataResult.franchise,
          wikidataExactRefCount: wikidataResult.refs.length,
          tmdbSearchRefCount: tmdbSearchRefs.length,
          exactRefCount: exactRefs.length,
          count: uniqueResults.length,
          results: uniqueResults
        })
      }

    if (url.pathname.endsWith("/amc-showtimes")) {
      const amcKey = Deno.env.get("AMC_API_KEY")
      if (!amcKey) {
        return Response.json({ ok: false, error: "AMC_API_KEY not configured" }, { status: 500 })
      }

      const filmTitle = (url.searchParams.get("title") ?? "").trim()
      const date = (url.searchParams.get("date") ?? "").trim()
      const lat = (url.searchParams.get("lat") ?? "").trim()
      const lon = (url.searchParams.get("lon") ?? "").trim()

      if (!filmTitle || !date || !lat || !lon) {
        return Response.json({ ok: false, error: "Missing required params: title, date, lat, lon" }, { status: 400 })
      }

      const amcURL = `https://api.amctheatres.com/v2/showtimes/views/current-location/${encodeURIComponent(date)}/${encodeURIComponent(lat)}/${encodeURIComponent(lon)}?page-size=100`

      // ?probe=1 hits a simple catalogue endpoint to check if the key has any access at all
      if (url.searchParams.get("probe") === "1") {
        const probeResp = await fetchWithTimeout("https://api.amctheatres.com/v2/theatres?page-size=1", {
          headers: { "X-AMC-Vendor-Key": amcKey, "Accept": "application/json" }
        }, 8000)
        const probeBody = await probeResp.text().catch(() => "(unreadable)")
        return Response.json({ ok: probeResp.ok, status: probeResp.status, body: probeBody })
      }

      // Regional KV cache keyed by (normalized title, date, lat rounded to 1dp, lon rounded to 1dp).
      // 1 decimal place ≈ 11km cell — everyone in the same metro searching the same film on the same
      // day shares one AMC API call instead of each hitting AMC individually.
      const bypassCache = url.searchParams.get("force_refresh") === "1" || url.searchParams.get("debug") === "1"
      const roundedLat = String(Math.round(Number(lat) / 5) * 5)
      const roundedLon = String(Math.round(Number(lon) / 5) * 5)
      // v4: cache entries now include real theatre coordinates; bump version to discard stale v3 entries
      const kvCacheKey = ["amc_v4", normalizeTitle(filmTitle), date, roundedLat, roundedLon]

      if (!bypassCache) {
        try {
          const kv = await Deno.openKv()
          const cached = await kv.get<{ theaters: any[], totalShowtimes: number, matchedShowtimes: number, cachedAt: number }>(kvCacheKey)
          if (cached.value !== null) {
            return Response.json({ ok: true, ...cached.value, cached: true })
          }
        } catch {
          // KV unavailable — fall through to live AMC call
        }
      }

      const amcResp = await fetchWithTimeout(amcURL, {
        headers: {
          "X-AMC-Vendor-Key": amcKey,
          "Accept": "application/json"
        }
      }, 10000)

      if (!amcResp.ok) {
        const errBody = await amcResp.text().catch(() => "(unreadable)")
        return Response.json({ ok: false, error: `AMC API error: ${amcResp.status}`, amcBody: errBody }, { status: 502 })
      }

      trackApiCall("amc")
      incrementServiceCall("amc")
      const amcData = await amcResp.json()

      // Pass ?debug=1 to see the raw AMC response for response shape diagnosis
      if (url.searchParams.get("debug") === "1") {
        return Response.json({ ok: true, raw: amcData })
      }

      const allShowtimes: any[] = amcData?._embedded?.showtimes ?? []

      // Pass ?theatre_shape=1 to inspect the raw showtime shape (diagnostic)
      if (url.searchParams.get("theatre_shape") === "1") {
        const first = allShowtimes[0] ?? null
        return Response.json({
          ok: true,
          total: allShowtimes.length,
          firstShowtimeKeys: first ? Object.keys(first) : null,
          firstShowtime: first
        })
      }

      // Filter to only showtimes for the requested film.
      // AMC v2 flat response uses st.movieName directly (no _embedded on individual showtimes).
      const matching = allShowtimes.filter((st: any) => {
        const name = st.movieName ?? st._embedded?.movie?.name ?? ""
        return matchScore(name, filmTitle) >= 60
      })

      // Get unique theatre IDs from matched showtimes, then fetch their details
      // (name + coordinates) in parallel — coordinates are NOT in the showtimes response.
      const uniqueTheatreIds: number[] = [...new Set(matching.map((st: any) => st.theatreId).filter(Boolean))]
      const amcHeaders = { "X-AMC-Vendor-Key": amcKey, "Accept": "application/json" }

      const theatreDetailResults = await Promise.all(
        uniqueTheatreIds.slice(0, 20).map(id =>
          fetchWithTimeout(`https://api.amctheatres.com/v2/theatres/${id}`, { headers: amcHeaders }, 6000)
            .then(r => r.ok ? r.json().catch(() => null) : null)
            .catch(() => null)
        )
      )

      // Parse coordinates tolerantly (number or string)
      const parseCoord = (v: any): number | null => {
        if (typeof v === "number" && !isNaN(v)) return v
        if (typeof v === "string" && v !== "") { const n = Number(v); return isNaN(n) ? null : n }
        return null
      }

      const theatreInfo = new Map<number, { name: string; lat: number | null; lon: number | null }>()
      for (const th of theatreDetailResults) {
        if (!th?.id) continue
        const loc = th.location ?? th._embedded?.location ?? {}
        theatreInfo.set(Number(th.id), {
          name: th.name ?? "AMC Theatre",
          lat: parseCoord(loc.lat) ?? parseCoord(loc.latitude) ?? null,
          lon: parseCoord(loc.lng) ?? parseCoord(loc.lon) ?? parseCoord(loc.longitude) ?? null
        })
      }

      // Group showtimes by theatreId
      const theatreMap = new Map<number, { name: string; lat: number | null; lon: number | null; entries: any[] }>()

      for (const st of matching) {
        const theatreId: number = Number(st.theatreId)
        if (!theatreMap.has(theatreId)) {
          const info = theatreInfo.get(theatreId)
          theatreMap.set(theatreId, {
            name: info?.name ?? "AMC Theatre",
            lat: info?.lat ?? null,
            lon: info?.lon ?? null,
            entries: []
          })
        }

        const rawTime: string = st.showDateTimeLocal ?? st.showDateTime ?? ""

        // Format: premiumFormat field, then attributes that match known format codes
        const premiumFormat = normalizeAMCFormat(
          typeof st.premiumFormat === "string" && st.premiumFormat ? st.premiumFormat : null
        )
        const attrFormat = premiumFormat == null
          ? (() => {
              const fmtAttr = (st.attributes ?? []).find((a: any) => normalizeAMCFormat(a.code ?? null) !== null)
              return fmtAttr ? normalizeAMCFormat(fmtAttr.code) : null
            })()
          : null
        const format = premiumFormat ?? attrFormat

        // Accessibility: known codes from attributes
        const knownAccessibility = ["CC", "OC", "AD", "AS", "HH", "HL", "CLOSEDCAPTION", "OPTICALLYCAPTIONED", "AUDIODESCRIPTION", "DESCRIPTIVEVIDEO", "ASSISTIVELISTENING", "HEARINGLOOP"]
        const accessibility: string[] = (st.attributes ?? [])
          .filter((a: any) => {
            const code = (a.code ?? "").toUpperCase()
            return knownAccessibility.some(k => code.includes(k))
          })
          .map((a: any) => a.name ?? a.code)
          .filter(Boolean)

        theatreMap.get(theatreId)!.entries.push({
          id: String(st.id ?? ""),
          startTime: rawTime,
          format,
          accessibility: accessibility.length > 0 ? accessibility : null,
          bookingURL: st.purchaseUrl ?? st.mobilePurchaseUrl ?? null
        })
      }

      const theaters = Array.from(theatreMap.values()).map(t => ({
        name: t.name,
        lat: t.lat,
        lon: t.lon,
        showtimes: t.entries.sort((a, b) => a.startTime.localeCompare(b.startTime))
      }))

      // Cache: 7 days for found results, 24h for empty (film may start showing soon).
      // cachedAt timestamp lets the iOS client show data freshness.
      const cachedAt = Date.now()
      const ttlMs = theaters.length > 0
        ? 7 * 24 * 60 * 60 * 1000
        : 24 * 60 * 60 * 1000
      try {
        const kv = await Deno.openKv()
        await kv.set(
          kvCacheKey,
          { theaters, totalShowtimes: allShowtimes.length, matchedShowtimes: matching.length, cachedAt },
          { expireIn: ttlMs }
        )
      } catch {
        // Non-fatal
      }

      return Response.json({ ok: true, totalShowtimes: allShowtimes.length, matchedShowtimes: matching.length, theaters, cachedAt, cached: false })
    }

    if (url.pathname.endsWith("/thematic-recommend")) {
      const aiKey = Deno.env.get("OPENROUTER_API_KEY")
      const aiKeyBackup = Deno.env.get("OPENROUTER_BACKUP_KEY")
      if (!aiKey) {
        return Response.json({ ok: false, error: "OPENROUTER_API_KEY not configured" }, { status: 500 })
      }

      const body = await req.json().catch(() => null)
      const query = typeof body?.query === "string" ? body.query.trim() : ""
      const filter = typeof body?.filter === "string" ? body.filter : "both"

      if (!query) {
        return Response.json({ ok: false, error: "Missing query" }, { status: 400 })
      }

      const mediaScope = filter === "movie" ? "movies only" : filter === "tv" ? "TV shows only" : "movies and TV shows"

      const systemPrompt = `You are a film and TV recommendation expert. Based on the user's description, list real, existing ${mediaScope} that best match.

Return one title per line in this exact format:
Title|Year

Rules:
- Return 20-25 titles. Must be real and actually exist.
- Lead with the strongest matches first.
- Prefer well-regarded titles. Vary directors, franchises, and eras.
- Return ONLY the list. No JSON, no markdown, no numbering, no explanations.`

      const openRouterBody = JSON.stringify({
        models: [
          "poolside/laguna-xs-2.1:free",
          "nvidia/nemotron-3.5-lightning:free",
          "liquid/lfm-2.5-2.6b:free"
        ],
        max_tokens: 800,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: query }
        ]
      })

      async function callOpenRouter(key: string): Promise<string | null> {
        try {
          const resp = await fetchWithTimeout("https://openrouter.ai/api/v1/chat/completions", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "Authorization": `Bearer ${key}`,
              "HTTP-Referer": "https://vestigo.app",
              "X-Title": "Vestigo"
            },
            body: openRouterBody
          }, 50000)
          if (!resp.ok) return null
          const data = await resp.json()
          return (data?.choices?.[0]?.message?.content ?? "").trim() || null
        } catch {
          return null
        }
      }

      let text = await callOpenRouter(aiKey)
      if (!text && aiKeyBackup) {
        text = await callOpenRouter(aiKeyBackup)
      }
      if (!text) {
        return Response.json({ ok: false, error: "Service is busy, please try again in a moment" }, { status: 503 })
      }

      const llmTitles = text
        .split('\n')
        .map((l: string) => l.replace(/^```[a-z]*/, '').replace(/^[0-9]+[.)]\s*/, '').replace(/^[-*•]\s*/, '').trim())
        .filter((l: string) => l.length > 0 && !l.startsWith('```') && l.includes('|'))
        .map((line: string) => {
          const pipeIdx = line.indexOf('|')
          const title = line.slice(0, pipeIdx).trim()
          const year = Number(line.slice(pipeIdx + 1).trim())
          return { title, year: Number.isFinite(year) && year > 1900 ? year : null }
        })
        .filter((item: any) => item.title.length > 0)

      if (llmTitles.length === 0) {
        return Response.json({ ok: false, error: "Service is busy, please try again in a moment" }, { status: 503 })
      }

      async function enrichOneTitle(item: any): Promise<any | null> {
        const titleStr = String(item.title ?? "").trim()
        if (!titleStr) return null
        try {
          if (filter === "tv") {
            const params: Record<string, string> = { query: titleStr, include_adult: "false" }
            if (typeof item.year === "number") params.first_air_date_year = String(item.year)
            const result = await fetchTMDb("/search/tv", params)
            const hit = Array.isArray(result.results) ? result.results[0] : null
            return hit && typeof hit.id === "number" ? { ...hit, media_type: "tv" } : null
          } else if (filter === "movie") {
            const params: Record<string, string> = { query: titleStr, include_adult: "false" }
            if (typeof item.year === "number") params.year = String(item.year)
            const result = await fetchTMDb("/search/movie", params)
            const hit = Array.isArray(result.results) ? result.results[0] : null
            return hit && typeof hit.id === "number" ? { ...hit, media_type: "movie" } : null
          } else {
            const result = await fetchTMDb("/search/multi", { query: titleStr, include_adult: "false" })
            const results = Array.isArray(result.results) ? result.results : []
            const hit = results.find((r: any) => r.media_type === "movie" || r.media_type === "tv") ?? null
            return hit && typeof hit.id === "number" ? hit : null
          }
        } catch {
          return null
        }
      }

      const enriched = await Promise.all(llmTitles.slice(0, 20).map(enrichOneTitle))
      const seen = new Set<string>()
      const titles = enriched.filter((item: any): item is NonNullable<typeof item> => {
        if (!item) return false
        const key = `${item.media_type ?? "unknown"}-${item.id}`
        if (seen.has(key)) return false
        seen.add(key)
        return true
      })

      trackApiCall("openrouter")
      incrementServiceCall("openrouter")
      await incrementAIUsage()
      return Response.json({ ok: true, titles })
    }

    if (url.pathname.endsWith("/youtube-shorts-filter")) {
      const keysParam = (url.searchParams.get("keys") ?? "").trim()
      const keys = keysParam.split(",").map(k => k.trim()).filter(k => k.length > 0)

      if (keys.length === 0) {
        return Response.json({ ok: true, shortKeys: [] })
      }

      async function isYouTubeShort(key: string): Promise<boolean> {
        try {
          const resp = await fetchWithTimeout(
            "https://www.youtube.com/youtubei/v1/player?key=AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8",
            {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                "User-Agent": "com.google.android.youtube/17.31.35 (Linux; U; Android 11) gzip"
              },
              body: JSON.stringify({
                videoId: key,
                context: {
                  client: {
                    clientName: "ANDROID",
                    clientVersion: "17.31.35",
                    androidSdkVersion: 30
                  }
                }
              })
            },
            8000
          )
          if (!resp.ok) return false
          const data = await resp.json()

          // Most reliable: YouTube's own canonical URL says /shorts/ for Shorts
          const canonical = String(data?.microformat?.playerMicroformatRenderer?.urlCanonical ?? "")
          if (canonical.length > 0) return canonical.includes("/shorts/")

          // Fallback: actual video format dimensions (portrait = Short)
          const formats: any[] = data?.streamingData?.adaptiveFormats ?? []
          const videoFmt = formats.find((f: any) => typeof f.width === "number" && typeof f.height === "number" && String(f.mimeType ?? "").startsWith("video/"))
          if (videoFmt) return Number(videoFmt.height) > Number(videoFmt.width)

          // Last resort: thumbnail dimensions
          const thumbnails: any[] = data?.videoDetails?.thumbnail?.thumbnails ?? []
          const thumb = thumbnails[thumbnails.length - 1]
          const tw = Number(thumb?.width ?? 0)
          const th = Number(thumb?.height ?? 0)
          if (tw > 0 && th > 0) return th > tw

          return false
        } catch {
          return false
        }
      }

      const checks = await Promise.all(keys.map(async key => ({ key, isShort: await isYouTubeShort(key) })))
      const shortKeys = checks.filter(({ isShort }) => isShort).map(({ key }) => key)

      // Count one call per video checked (not per short found)
      for (let i = 0; i < keys.length; i++) incrementServiceCall("youtube")

      return Response.json({ ok: true, shortKeys })
    }

    if (url.pathname.endsWith("/service-usage")) {
      const days = Math.min(Math.max(Number(url.searchParams.get("days") ?? "30"), 1), 90)
      const counts = await getServiceUsage(days)
      return Response.json({ ok: true, days, counts })
    }

    if (url.pathname.endsWith("/charts")) {
      const rawKind = String(url.searchParams.get("kind") ?? "movie").toLowerCase()
      if (rawKind !== "movie" && rawKind !== "tv") {
        return Response.json({ ok: false, error: "kind must be movie or tv" }, { status: 400 })
      }
      const kind = rawKind as "movie" | "tv"
      const ranking = url.searchParams.get("ranking") === "tmdb" ? "tmdb" : "imdb"
      const forceRefresh = url.searchParams.get("force_refresh") === "1"

      const tmdbCacheKey = `charts_tmdb_${kind}_v3`
      const imdbCacheKey = `charts_imdb_${kind}_v3`

      // Serve from cache if fresh
      if (!forceRefresh) {
        const requestedKey = ranking === "tmdb" ? tmdbCacheKey : imdbCacheKey
        const cached = await getChartCache(requestedKey)
        if (cached && isCacheFresh(cached.updatedAt)) {
          return Response.json({ ok: true, items: cached.items, updatedAt: cached.updatedAt, source: "cache", ranking })
        }
      }

      // Fetch 7 pages of results in parallel (~140 item pool).
      // Movies use /discover/movie with without_genres=10770 so TMDb excludes TV Movies
      // (e.g. Doctor Who specials) at the query level — more reliable than post-filter.
      // TV uses /tv/top_rated which has no equivalent issue.
      const allResults: any[] = []
      await Promise.all(
        [1,2,3,4,5,6,7].map(async (page) => {
          try {
            let data: any
            if (kind === "movie") {
              data = await fetchTMDb("/discover/movie", {
                sort_by: "vote_average.desc",
                "vote_count.gte": "3000",
                without_genres: "10770",
                include_adult: "false",
                page: String(page)
              })
            } else {
              data = await fetchTMDb("/tv/top_rated", { page: String(page) })
            }
            if (Array.isArray(data.results)) allResults.push(...data.results)
          } catch {}
        })
      )

      // Dedupe and build base DTOs
      const seen = new Set<number>()
      const pool = allResults
        .filter(item => {
          if (!Number.isFinite(item?.id) || seen.has(item.id)) return false
          seen.add(item.id)
          return true
        })
        .map(item => {
          const dto = kind === "movie" ? tmdbMovieDTO(item) : tmdbTVDTO(item)
          return { ...dto, overview: dto.overview.slice(0, 250) }
        })

      // Enrich all pool items with IMDb IDs + OMDb ratings
      const enriched = await enrichPoolWithRatings(kind, pool)

      // TMDb list: top 100 by vote_average
      const tmdbList = [...enriched]
        .sort((a, b) => (b.voteAverage ?? 0) - (a.voteAverage ?? 0))
        .slice(0, 100)

      // IMDb list: top 100 by IMDb rating, TMDb as tiebreaker for unrated items
      const imdbList = [...enriched]
        .sort((a, b) => {
          const ar = typeof a.imdbRating === "number" ? a.imdbRating : -1
          const br = typeof b.imdbRating === "number" ? b.imdbRating : -1
          if (br !== ar) return br - ar
          return (b.voteAverage ?? 0) - (a.voteAverage ?? 0)
        })
        .slice(0, 100)

      const updatedAt = new Date().toISOString()
      await Promise.all([
        setChartCache(tmdbCacheKey, tmdbList),
        setChartCache(imdbCacheKey, imdbList)
      ])

      const items = ranking === "tmdb" ? tmdbList : imdbList
      return Response.json({ ok: true, items, updatedAt, source: "fresh", ranking })
    }

    return Response.json(
      {
        error: "Not found",
        path: url.pathname
      },
      {
        status: 404
      }
    )
  } catch (error) {
    return Response.json(
      {
        ok: false,
        error: error instanceof Error ? error.message : "Unknown error"
      },
      {
        status: 500
      }
    )
  }
})
