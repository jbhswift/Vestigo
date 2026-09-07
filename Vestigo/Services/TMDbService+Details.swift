import Foundation

extension TMDbService {

    func detail(for item: MediaItem, regionCode: String = "US") async throws -> MediaDetail {
        let response: TMDbDetailResponse = try await fetch(path: "/\(item.kind.tmdbPath)/\(item.id)", query: [URLQueryItem(
            name: "append_to_response",
            value: item.kind == .movie
            ? "credits,similar,recommendations,keywords,watch/providers,release_dates,videos,external_ids"
            : "credits,similar,recommendations,keywords,watch/providers,content_ratings,videos,external_ids,networks"
        )])

        guard item.kind == .tv else {
            return MediaDetail(response: response, fallback: item, regionCode: regionCode)
        }

        let seasonsWithEpisodes = try await hydratedSeasons(for: item, baseSeasons: response.seasons ?? [])
        let hydratedResponse = response.replacingSeasons(seasonsWithEpisodes)
        return MediaDetail(response: hydratedResponse, fallback: item, regionCode: regionCode)
    }

    private func hydratedSeasons(for item: MediaItem, baseSeasons: [SeasonDTO]) async throws -> [SeasonDTO] {
        var indexed: [(Int, SeasonDTO)] = []
        await withTaskGroup(of: (Int, SeasonDTO?).self) { group in
            for (index, season) in baseSeasons.enumerated() {
                group.addTask {
                    guard let seasonNumber = season.seasonNumber, seasonNumber > 0 else {
                        return (index, nil)
                    }
                    let hydrated: SeasonDTO? = try? await self.fetch(path: "/tv/\(item.id)/season/\(seasonNumber)", query: [])
                    return (index, hydrated)
                }
            }
            // mergingEpisodes is @MainActor – run it here in the group body (inherits caller's actor)
            for await (index, hydrated) in group {
                let base = baseSeasons[index]
                indexed.append((index, hydrated.map { base.mergingEpisodes(from: $0) } ?? base))
            }
        }
        return indexed.sorted { $0.0 < $1.0 }.map(\.1)
    }

    func personCredits(personID: Int) async throws -> PersonCreditBundle {
        let response: TMDbPersonCreditsResponse = try await fetch(path: "/person/\(personID)/combined_credits", query: [])
        let byRatingThenDate: (MediaItem, MediaItem) -> Bool = { lhs, rhs in
            if lhs.voteAverage != rhs.voteAverage { return lhs.voteAverage > rhs.voteAverage }
            return (lhs.releaseDateValue ?? .distantPast) > (rhs.releaseDateValue ?? .distantPast)
        }
        let onScreen = response.cast
            .map { MediaItem($0) }
            .filter { $0.shouldShowInPersonCredits }
            .uniqued()
            .sorted(by: byRatingThenDate)
        let behindCamera = response.crew
            .map { MediaItem($0) }
            .filter { $0.shouldShowInPersonCredits }
            .uniqued()
            .sorted(by: byRatingThenDate)
        return PersonCreditBundle(onScreen: onScreen, behindCamera: behindCamera)
    }

    func personDetail(personID: Int) async throws -> PersonDetail {
        let response: TMDbPersonDetailResponse = try await fetch(path: "/person/\(personID)", query: [])
        return PersonDetail(response: response)
    }

    func recommendations(for key: MediaKey) async throws -> [MediaItem] {
        try await fetchList(path: "/\(key.kind.tmdbPath)/\(key.id)/recommendations", query: [])
            .filter { $0.shouldShowInDiscovery && !$0.isUpcoming }
    }

    func sameSeriesOrSimilar(for key: MediaKey) async throws -> [MediaItem] {
        try await fetchList(path: "/\(key.kind.tmdbPath)/\(key.id)/similar", query: [])
            .filter { $0.shouldShowInDiscovery && !$0.isUpcoming }
    }

    func item(for key: MediaKey) async throws -> MediaItem {
        let response: TMDbStandaloneMediaDTO = try await fetch(path: "/\(key.kind.tmdbPath)/\(key.id)", query: [])
        return MediaItem(
            id: response.id,
            kind: key.kind,
            title: response.title ?? response.name ?? "",
            overview: response.overview ?? "",
            posterPath: response.posterPath,
            backdropPath: response.backdropPath,
            releaseDate: response.releaseDate ?? response.firstAirDate,
            voteAverage: response.voteAverage ?? 0,
            voteCount: response.voteCount,
            genreIDs: response.genres?.map(\.id) ?? [],
            creditRole: nil,
            runtime: response.runtime,
            originalLanguage: response.originalLanguage
        )
    }

    func items(for keys: [MediaKey]) async throws -> [MediaItem] {
        let validKeys = keys.filter { $0.kind == .movie || $0.kind == .tv }.prefix(40)
        return try await withThrowingTaskGroup(of: MediaItem?.self) { group in
            for key in validKeys {
                group.addTask { try? await self.item(for: key) }
            }
            var results: [MediaItem] = []
            for try await item in group {
                if let item { results.append(item) }
            }
            return results.uniqued()
        }
    }

    // MARK: - Lightweight fetches for background notifications

    func seasonCount(forTVShowID id: Int) async throws -> Int {
        struct LightResponse: Decodable {
            let numberOfSeasons: Int?
            enum CodingKeys: String, CodingKey { case numberOfSeasons = "number_of_seasons" }
        }
        let response: LightResponse = try await fetch(path: "/tv/\(id)", query: [])
        return response.numberOfSeasons ?? 0
    }

    func trailerCount(for item: MediaItem) async throws -> Int {
        struct LightResponse: Decodable {
            struct VideosResponse: Decodable {
                let results: [VideoResult]
                struct VideoResult: Decodable { let type: String; let site: String }
            }
            let videos: VideosResponse?
            enum CodingKeys: String, CodingKey { case videos }
        }
        let response: LightResponse = try await fetch(
            path: "/\(item.kind.tmdbPath)/\(item.id)",
            query: [URLQueryItem(name: "append_to_response", value: "videos")]
        )
        return response.videos?.results.filter { $0.type == "Trailer" && $0.site == "YouTube" }.count ?? 0
    }
}
