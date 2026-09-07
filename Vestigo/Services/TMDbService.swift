import Foundation

struct TMDbService {
    private let base = "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api"

    func trending(filter: MediaFilter) async throws -> [MediaItem] {
        try await fetchList(path: "/trending/\(filter.tmdbPath)/week", query: [])
    }

    func popular(filter: MediaFilter) async throws -> [MediaItem] {
        if filter == .both {
            async let movies = fetchList(path: "/movie/popular", query: [])
            async let tv = fetchList(path: "/tv/popular", query: [])
            return try await (movies + tv).sorted { $0.voteAverage > $1.voteAverage }
        }
        return try await fetchList(path: "/\(filter.tmdbPath)/popular", query: [])
    }

    func newReleases(filter: MediaFilter) async throws -> [MediaItem] {
        var items: [MediaItem] = []
        var firstError: Error?

        if filter != .tv {
            do {
                items += try await fetchList(path: "/movie/now_playing", query: [URLQueryItem(name: "region", value: "US")])
            } catch {
                firstError = firstError ?? error
            }
        }

        if filter != .movie {
            do {
                items += try await fetchList(path: "/tv/on_the_air", query: [])
            } catch {
                firstError = firstError ?? error
            }
        }

        if items.isEmpty, let firstError {
            throw firstError
        }

        return items.uniqued()
    }

    func upcoming(filter: MediaFilter) async throws -> [MediaItem] {
        var items: [MediaItem] = []
        var firstError: Error?

        if filter != .tv {
            do {
                items += try await fetchListPages(path: "/movie/upcoming", query: [URLQueryItem(name: "region", value: "US")], pages: 3)
            } catch {
                firstError = firstError ?? error
            }
        }

        if filter != .movie {
            do {
                items += try await fetchListPages(path: "/discover/tv", query: [
                    URLQueryItem(name: "first_air_date.gte", value: DateParser.tmdbDateString(from: Date())),
                    URLQueryItem(name: "sort_by", value: "popularity.desc"),
                    URLQueryItem(name: "include_null_first_air_dates", value: "false")
                ], pages: 2)
            } catch {
                firstError = firstError ?? error
            }
        }

        if items.isEmpty, let firstError {
            throw firstError
        }

        return items.uniqued()
    }

    func topRated(kind: MediaKind, pages: Int = 5) async throws -> [MediaItem] {
        guard kind == .movie || kind == .tv else { return [] }
        let path = "/\(kind.tmdbPath)/top_rated"
        return try await withThrowingTaskGroup(of: [MediaItem].self) { group in
            for page in 1...max(pages, 1) {
                group.addTask { try await self.fetchList(path: path, query: [], page: page) }
            }
            var all: [MediaItem] = []
            for try await pageItems in group { all += pageItems }
            return all.uniqued().sorted { $0.voteAverage > $1.voteAverage }
        }
    }

    func search(query: String, filter: MediaFilter, includeAdult: Bool = false) async throws -> [MediaItem] {
        let path = filter == .both ? "/search/multi" : "/search/\(filter.tmdbPath)"
        return try await fetchList(path: path, query: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: includeAdult ? "true" : "false")
        ])
        .filter { $0.kind != .person }
    }

    func searchPeople(query: String, includeAdult: Bool = false) async throws -> [PersonSummary] {
        let response: TMDbPersonSearchResponse = try await fetch(path: "/search/person", query: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "include_adult", value: includeAdult ? "true" : "false")
        ])

        return response.results
            .map { dto in
                PersonSummary(dto, fallbackRole: dto.knownForDepartment ?? "Person")
            }
            .uniquedPeople()
    }

    func contextualSearch(query: String, filter: MediaFilter, includeAdult: Bool = false) async throws -> [MediaItem] {
        let found = try await search(query: query, filter: filter, includeAdult: includeAdult)
        return await withTaskGroup(of: [MediaItem].self) { group in
            for item in found {
                group.addTask { (try? await self.recommendations(for: item.key)) ?? [] }
                group.addTask { (try? await self.sameSeriesOrSimilar(for: item.key)) ?? [] }
            }
            var more: [MediaItem] = []
            for await batch in group { more += batch }
            return more
        }
    }

    // MARK: - Thematic search support

    func personIDs(for name: String) async throws -> [Int] {
        let response: TMDbPersonSearchResponse = try await fetch(path: "/search/person", query: [
            URLQueryItem(name: "query", value: name),
            URLQueryItem(name: "include_adult", value: "false")
        ])
        // Filter by popularity to avoid matching obscure people who share a name with well-known figures
        let qualified = response.results.filter { ($0.popularity ?? 0) > 5.0 }
        return Array(qualified.prefix(2).map(\.id))
    }

    func keywordIDs(for term: String) async throws -> [Int] {
        let response: TMDbKeywordsResponse = try await fetch(path: "/search/keyword", query: [
            URLQueryItem(name: "query", value: term)
        ])
        return Array((response.results ?? []).prefix(3).map(\.id))
    }

    // MARK: - Core fetch helpers

    func fetchList(path: String, query: [URLQueryItem]) async throws -> [MediaItem] {
        let response: TMDbListResponse = try await fetch(path: path, query: query)
        return response.results.map(MediaItem.init).filter { !$0.title.isEmpty }
    }

    func fetchListPages(path: String, query: [URLQueryItem], pages: Int) async throws -> [MediaItem] {
        var collected: [MediaItem] = []
        for page in 1...max(pages, 1) {
            let pageItems: [MediaItem] = try await fetchList(path: path, query: query, page: page)
            collected += pageItems
            if pageItems.isEmpty { break }
        }
        return collected.uniqued()
    }

    func fetchList(path: String, query: [URLQueryItem], page: Int) async throws -> [MediaItem] {
        let response: TMDbListResponse = try await fetch(path: path, query: query, page: page)
        return response.results.map(MediaItem.init).filter { !$0.title.isEmpty }
    }

    func fetch<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        try await fetch(path: path, query: query, page: 1)
    }

    func fetch<T: Decodable>(path: String, query: [URLQueryItem], page: Int) async throws -> T {
        var comps = URLComponents(string: base + "/tmdb-proxy")!
        comps.queryItems = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "page", value: String(page))
        ] + query
        guard let url = comps.url else { throw URLError(.badURL) }
        let (data, response) = try await URLSession.shared.data(from: url)
        AnalyticsService.shared.track(.apiCallMade(service: "tmdb"))
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
