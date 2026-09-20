import SwiftUI
import Foundation

extension VestigoModel {

    func loadSmartRecommendations() async {
        let watchedHistory = library.watchedItems
        guard watchedHistory.count >= 3 else {
            recommendations = []
            moreLikeLastWatched = []
            moreLikeFavourite = []
            fromTopGenre = []
            trySomethingNewRecommendations = []
            seriesNext = []
            return
        }

        let strength = min(max(settings.recommendationStrength, 1), 5)
        let normalizedStrength = (strength - 1) / 4
        // Lower values broaden recommendations; higher values lean harder on highly rated watched history.
        let unratedWatchedWeight = 0.65 - (normalizedStrength * 0.45)
        let ratingInfluence = 0.35 + (normalizedStrength * 0.65)
        let lowRatingPenaltyMultiplier = 0.15 + (normalizedStrength * 0.85)

        func historyWeight(for historyItem: MediaItem) -> Double {
            let rating = library.ratings[historyItem.key]

            if let rating {
                let centeredRating = (rating - 2.5) / 2.5
                if centeredRating >= 0 {
                    return 1.0 + centeredRating * ratingInfluence
                } else {
                    return centeredRating * lowRatingPenaltyMultiplier
                }
            } else {
                return unratedWatchedWeight
            }
        }

        func genreSimilarity(_ candidate: MediaItem, _ historyItem: MediaItem) -> Double {
            let candidateGenres = Set(candidate.genreIDs)
            let historyGenres = Set(historyItem.genreIDs)
            guard !candidateGenres.isEmpty, !historyGenres.isEmpty else { return 0 }

            let overlap = candidateGenres.intersection(historyGenres).count
            let possible = max(candidateGenres.union(historyGenres).count, 1)
            return Double(overlap) / Double(possible)
        }

        let historyLimit = strength >= 4 ? 10 : 14
        let rankedHistory = watchedHistory
            .sorted { lhs, rhs in
                let lhsRating = library.ratings[lhs.key] ?? 2.5
                let rhsRating = library.ratings[rhs.key] ?? 2.5

                if lhsRating != rhsRating {
                    return lhsRating > rhsRating
                }

                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
            .prefix(historyLimit)

        var scoredRecommendations: [MediaKey: (item: MediaItem, score: Double)] = [:]
        var nextItems: [MediaItem] = []

        let notInterestedSeeds = library.notInterestedItems

        func notInterestedDownweight(for candidate: MediaItem) -> Double {
            if library.isNotInterested(candidate.key) {
                return 0.03
            }

            guard !notInterestedSeeds.isEmpty else { return 1.0 }

            let candidateGenres = Set(candidate.genreIDs)
            guard !candidateGenres.isEmpty else { return 1.0 }

            for seed in notInterestedSeeds {
                let seedGenres = Set(seed.genreIDs)
                guard !seedGenres.isEmpty else { continue }
                let overlap = candidateGenres.intersection(seedGenres).count
                let union = candidateGenres.union(seedGenres).count
                let similarity = union == 0 ? 0.0 : Double(overlap) / Double(union)
                if similarity >= 0.75 && candidate.kind == seed.kind {
                    return 0.75
                }
            }

            return 1.0
        }

        for record in rankedHistory {
            let weight = historyWeight(for: record)

            do {
                let rec = try await tmdb.recommendations(for: record.key)

                for (index, candidate) in rec.enumerated() {
                    guard !library.isWatched(candidate.key) else { continue }
                    guard !library.isNeverShowAgain(candidate.key) else { continue }

                    let positionScore = 1.0 / (1.0 + Double(index) * 0.08)
                    let similarityBoost = genreSimilarity(candidate, record) * (0.35 + normalizedStrength * 0.45)
                    let score = (positionScore + similarityBoost) * weight * notInterestedDownweight(for: candidate)

                    var entry = scoredRecommendations[candidate.key] ?? (candidate, 0)
                    entry.score += score
                    scoredRecommendations[candidate.key] = entry
                }

                let related = try await tmdb.sameSeriesOrSimilar(for: record.key)
                nextItems.append(contentsOf: related)
            } catch { }
        }

        let sortedRecommendations = scoredRecommendations.values
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score {
                    return lhs.score > rhs.score
                }

                let lhsRating = ratingSortValue(for: lhs.item)
                let rhsRating = ratingSortValue(for: rhs.item)
                if lhsRating != rhsRating {
                    return lhsRating > rhsRating
                }

                return (lhs.item.releaseDateValue ?? .distantPast) > (rhs.item.releaseDateValue ?? .distantPast)
            }
            .map(\.item)

        let visibleRecommendations = preparedResults(
            sortedRecommendations.filter { !library.isWatched($0.key) && !library.isNeverShowAgain($0.key) },
            hideWatched: true
        )
        recommendations = await filteredContentCleanupIfNeeded(
            visibleRecommendations,
            hideShortFilms: settings.hideShortFilmsFromRecommended,
            hideExtrasAndPromos: settings.hideExtrasAndPromosFromRecommended
        )
        seriesNext = await filteredContentCleanupIfNeeded(
            preparedResults(nextItems.uniqued().filter { !library.isWatched($0.key) && !library.isNeverShowAgain($0.key) && $0.kind == .tv }, hideWatched: true),
            hideShortFilms: settings.hideShortFilmsFromRecommended,
            hideExtrasAndPromos: settings.hideExtrasAndPromosFromRecommended
        )

        if let lastWatched = library.lastWatchedItem {
            let prepared = preparedResults(
                await universalMoreLikeThis(for: lastWatched, hideWatched: true, limit: 80),
                hideWatched: true
            )
            if prepared.isEmpty {
                moreLikeLastWatched = []
            } else {
                moreLikeLastWatched = await filteredContentCleanupIfNeeded(
                    prepared,
                    hideShortFilms: settings.hideShortFilmsFromRecommended,
                    hideExtrasAndPromos: settings.hideExtrasAndPromosFromRecommended
                )
            }
        } else {
            moreLikeLastWatched = []
        }

        var favouriteRecommendations: [MediaItem] = []
        let favouriteSeeds = library.favouriteItems
            .sorted { lhs, rhs in
                let lhsRating = library.ratings[lhs.key] ?? 2.5
                let rhsRating = library.ratings[rhs.key] ?? 2.5
                if lhsRating != rhsRating { return lhsRating > rhsRating }
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

        for favourite in favouriteSeeds.prefix(6) {
            favouriteRecommendations.append(contentsOf: await universalMoreLikeThis(for: favourite, hideWatched: true, limit: 35))
        }

        if !favouriteSeeds.isEmpty {
            let prepared = preparedResults(
                favouriteRecommendations.uniqued(),
                hideWatched: true
            )
            moreLikeFavourite = await filteredContentCleanupIfNeeded(
                prepared,
                hideShortFilms: settings.hideShortFilmsFromRecommended,
                hideExtrasAndPromos: settings.hideExtrasAndPromosFromRecommended
            )
        } else {
            moreLikeFavourite = []
        }

        let watchedGenreIDs = watchedHistory.flatMap(\.genreIDs)
        if let topGenreID = watchedGenreIDs.frequencySorted().first {
            let preparedTopGenre = visibleRecommendations
                .filter { $0.shouldShowInDiscovery && !$0.isUpcoming && $0.genreIDs.contains(topGenreID) }
                .filter { !library.isNeverShowAgain($0.key) }
                .filter { settings.prioritiseEnglish ? (($0.originalLanguage ?? "en") == "en") : true }

            fromTopGenre = await filteredContentCleanupIfNeeded(
                preparedTopGenre,
                hideShortFilms: settings.hideShortFilmsFromRecommended,
                hideExtrasAndPromos: settings.hideExtrasAndPromosFromRecommended
            )
        } else {
            fromTopGenre = []
        }

        let watchedGenreSet = Set(watchedGenreIDs)
        let trySomethingNewPool = (popular + trending + newReleases)
                .uniqued()
                .filter { item in
                    !item.isUpcoming &&
                    !library.isWatched(item.key) &&
                    !library.isNeverShowAgain(item.key) &&
                    watchedGenreSet.isDisjoint(with: Set(item.genreIDs)) &&
                    (settings.prioritiseEnglish ? ((item.originalLanguage ?? "en") == "en") : true)
                }

        let preparedTrySomethingNew = preparedResults(
            trySomethingNewPool
                .sorted { lhs, rhs in
                    let lhsRating = ratingSortValue(for: lhs)
                    let rhsRating = ratingSortValue(for: rhs)
                    if lhsRating != rhsRating {
                        return lhsRating > rhsRating
                    }

                    return (lhs.releaseDateValue ?? .distantPast) > (rhs.releaseDateValue ?? .distantPast)
                },
            hideWatched: true
        )

        trySomethingNewRecommendations = await filteredContentCleanupIfNeeded(
            preparedTrySomethingNew,
            hideShortFilms: settings.hideShortFilmsFromRecommended,
            hideExtrasAndPromos: settings.hideExtrasAndPromosFromRecommended
        )

        saveCurrentHomeFeedCache()
    }

    func loadTopRated(kind: MediaKind) async {
        try? await loadTopRatedThrowing(kind: kind)
    }

    var chartCacheCount: Int {
        ["movie", "tv"].flatMap { kind in
            ["imdb", "tmdb"].map { ranking in "Vestigo.chartCache.v3.\(kind).\(ranking)" }
        }
        .filter { UserDefaults.standard.data(forKey: $0) != nil }
        .count
    }

    func clearChartCache() {
        for kind in ["movie", "tv"] {
            for ranking in ["imdb", "tmdb"] {
                UserDefaults.standard.removeObject(forKey: "Vestigo.chartCache.v3.\(kind).\(ranking)")
            }
        }
        topRatedMovies = []
        topRatedShows = []
    }

    func loadTopRatedThrowing(kind: MediaKind) async throws {
        guard kind == .movie || kind == .tv else { return }
        let ranking = settings.preferredRatingSource

        // Pre-populate from local cache immediately — eliminates spinner on repeat visits
        restoreChartFromLocalCache(kind: kind, ranking: ranking)

        // Skip network fetch if the local cache is still within its 7-day window
        if isChartLocalCacheFresh(kind: kind, ranking: ranking) { return }

        let chartItems = try await backend.chart(kind: kind, ranking: ranking)
        let items = chartItems.map(\.mediaItem)
        for dto in chartItems {
            let ratings = ExternalRatings(
                imdbID: dto.imdbID,
                imdbRating: dto.imdbRating,
                imdbVotes: dto.imdbVotes,
                rottenTomatoesRating: dto.rottenTomatoesRating,
                rottenTomatoesText: dto.rottenTomatoesText
            )
            if ratings.hasAnyRating {
                externalRatingsCache[dto.mediaItem.key] = ratings
            }
        }
        if kind == .movie { topRatedMovies = items } else { topRatedShows = items }
        saveChartToLocalCache(kind: kind, ranking: ranking, chartItems: chartItems)
    }

    // MARK: - Local chart cache (UserDefaults, 7-day TTL)

    private struct ChartCacheEntry: Codable {
        let item: MediaItem
        let ratings: ExternalRatings?
    }

    private struct ChartCacheRecord: Codable {
        let entries: [ChartCacheEntry]
        let savedAt: Date
    }

    private func chartLocalCacheKey(kind: MediaKind, ranking: RatingSource) -> String {
        "Vestigo.chartCache.v3.\(kind.rawValue).\(ranking.rawValue)"
    }

    private func restoreChartFromLocalCache(kind: MediaKind, ranking: RatingSource) {
        let key = chartLocalCacheKey(kind: kind, ranking: ranking)
        guard let data = UserDefaults.standard.data(forKey: key),
              let record = try? JSONDecoder().decode(ChartCacheRecord.self, from: data),
              !record.entries.isEmpty else { return }
        let items = record.entries.map(\.item)
        for entry in record.entries {
            if let ratings = entry.ratings {
                externalRatingsCache[entry.item.key] = ratings
            }
        }
        if kind == .movie { topRatedMovies = items } else { topRatedShows = items }
    }

    private func isChartLocalCacheFresh(kind: MediaKind, ranking: RatingSource) -> Bool {
        let key = chartLocalCacheKey(kind: kind, ranking: ranking)
        guard let data = UserDefaults.standard.data(forKey: key),
              let record = try? JSONDecoder().decode(ChartCacheRecord.self, from: data) else { return false }
        return Date().timeIntervalSince(record.savedAt) < 7 * 24 * 60 * 60
    }

    private func saveChartToLocalCache(kind: MediaKind, ranking: RatingSource, chartItems: [BackendChartItemDTO]) {
        let entries = chartItems.map { dto in
            let ratings = ExternalRatings(
                imdbID: dto.imdbID,
                imdbRating: dto.imdbRating,
                imdbVotes: dto.imdbVotes,
                rottenTomatoesRating: dto.rottenTomatoesRating,
                rottenTomatoesText: dto.rottenTomatoesText
            )
            return ChartCacheEntry(item: dto.mediaItem, ratings: ratings.hasAnyRating ? ratings : nil)
        }
        guard let data = try? JSONEncoder().encode(ChartCacheRecord(entries: entries, savedAt: Date())) else { return }
        UserDefaults.standard.set(data, forKey: chartLocalCacheKey(kind: kind, ranking: ranking))
    }
}
