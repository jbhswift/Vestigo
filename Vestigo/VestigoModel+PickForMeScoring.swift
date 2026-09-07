import SwiftUI
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

extension VestigoModel {

    func pickForMeRuntimeAllows(_ item: MediaItem, runtimeRange: PickForMeRuntimeRange) -> Bool {
        guard item.kind == .movie else { return true }
        guard runtimeRange.hasConstraint else { return true }
        guard let minutes = detailsCache[item.key]?.runtime ?? item.runtime else { return true }

        return runtimeRange.contains(minutes)
    }

    func loadPickForMeStrictFilterDetails(for items: [MediaItem], answers: PickForMeAnswers) async {
        await withTaskGroup(of: Void.self) { group in
            for item in items.prefix(120) where detailsCache[item.key] == nil {
                group.addTask { [weak self] in
                    guard let self else { return }
                    do {
                        let detail = try await self.tmdb.detail(for: item, regionCode: self.settings.streamingRegion.rawValue)
                        await MainActor.run { self.detailsCache[item.key] = detail }
                    } catch { }
                }
            }
        }
    }

    func pickForMeReleaseAgeAllows(_ item: MediaItem, releaseAge: PickForMeReleaseAge?) -> Bool {
        guard let releaseAge, releaseAge != .noPreference else { return true }
        guard let releaseDate = item.releaseDateValue else { return false }
        let now = Date()
        guard releaseDate <= now else { return false }

        if releaseAge == .newReleases {
            guard let cutoffDate = Calendar.current.date(byAdding: .month, value: -6, to: now) else {
                return false
            }
            return releaseDate >= cutoffDate
        }

        let yearsOld = Calendar.current.dateComponents([.year], from: releaseDate, to: now).year ?? 0

        if let maximumYearsOld = releaseAge.maximumYearsOld {
            return yearsOld <= maximumYearsOld
        }

        if let minimumYearsOld = releaseAge.minimumYearsOld {
            return yearsOld > minimumYearsOld
        }

        return true
    }

    func pickForMeDocumentaryAllows(_ item: MediaItem, answers: PickForMeAnswers) -> Bool {
        guard answers.wantsDocumentary else { return true }
        return item.genreIDs.contains(99)
    }

    func pickForMeSourceMaterialAllows(_ item: MediaItem, sourceMaterial: PickForMeSourceMaterial?, sourceMaterialCandidateKeys: Set<MediaKey>) -> Bool {
        guard let sourceMaterial, sourceMaterial != .noPreference else { return true }
        if sourceMaterialCandidateKeys.contains(item.key) { return true }

        let text = pickForMeSearchableText(for: item)
        return pickForMeSourceMaterialTextMatches(text, sourceMaterial: sourceMaterial)
    }

    func pickForMeSourceMaterialScore(item: MediaItem, text: String, sourceMaterial: PickForMeSourceMaterial, sourceMaterialCandidateKeys: Set<MediaKey>) -> Double {
        guard sourceMaterial != .noPreference else { return 0 }
        if sourceMaterialCandidateKeys.contains(item.key) || pickForMeSourceMaterialTextMatches(text, sourceMaterial: sourceMaterial) {
            return 18.0
        }

        return -1.5
    }

    func pickForMeSourceMaterialTextMatches(_ text: String, sourceMaterial: PickForMeSourceMaterial) -> Bool {
        switch sourceMaterial {
        case .book:
            return text.containsAny(["based on the novel", "based on a novel", "based on the book", "based on a book", "adapted from the novel", "adapted from a novel", "book by", "novel by"])
        case .game:
            return text.containsAny(["based on the video game", "based on a video game", "video game", "videogame", "game series", "computer game"])
        case .noPreference:
            return true
        }
    }

    func pickForMeFictionAllows(_ item: MediaItem, answers: PickForMeAnswers) -> Bool {
        guard let pref = answers.fictionPreference, !pref.isAnyOption else { return true }
        let genres = Set(item.genreIDs)
        let text = pickForMeSearchableText(for: item)

        switch pref {
        case .nonFiction:
            return genres.contains(99) || pickForMeIsNonfictionOrTrueEvent(genres: genres, text: text)
        case .basedOnTrueStory:
            return pickForMeIsNonfictionOrTrueEvent(genres: genres, text: text)
        case .fiction, .noPreference:
            return true
        }
    }

    func pickForMeHistoryAllows(_ item: MediaItem, answers: PickForMeAnswers) -> Bool {
        guard answers.wantsStrictHistorical else { return true }

        let historicalScore = pickForMeHistoricalEventScore(genres: Set(item.genreIDs), text: pickForMeSearchableText(for: item))
        return historicalScore > 0
    }

    func pickForMeScore(_ item: MediaItem, answers: PickForMeAnswers, sourceMaterialCandidateKeys: Set<MediaKey>) -> Double {
        let primaryAlignment = pickForMePrimaryArchetypeAlignmentScore(item, answers: answers)
        var score = primaryAlignment * 15.0  // was 13.0 — compensates for removed Groq +20 bonus
        let genreIDs = Set(item.genreIDs)
        let text = pickForMeSearchableText(for: item)

        if library.isNotInterested(item.key) {
            score -= 40.0
        }

        if library.isNeverShowAgain(item.key) {
            score -= 250.0
        }

        score += pickForMePrimaryArchetypeSoftGateAdjustment(primaryAlignment, answers: answers)

        let primaryArchetypeScores = answers.archetypes.map { archetype in
            pickForMeArchetypeScore(item: item, archetype: archetype)
        }

        for (archetype, archetypeScore) in zip(answers.archetypes, primaryArchetypeScores) {
            score += archetypeScore * (archetype == .surprise ? 0.65 : 1.0)
        }

        for secondaryArchetype in answers.secondaryArchetypes where !secondaryArchetype.isAnyOption {
            score += pickForMeArchetypeScore(item: item, archetype: secondaryArchetype) * 0.42
        }

        score += pickForMeArchetypeCombinationBonus(primaryScores: primaryArchetypeScores)

        for genrePreference in answers.genrePreferences where !genrePreference.isAnyOption {
            score += pickForMeGenrePreferenceScore(genres: genreIDs, text: text, genrePreference: genrePreference)
        }

        if let sourceMaterial = answers.sourceMaterial {
            score += pickForMeSourceMaterialScore(item: item, text: text, sourceMaterial: sourceMaterial, sourceMaterialCandidateKeys: sourceMaterialCandidateKeys)
        }

        score += pickForMeAnswerFulfillmentScore(
            item: item,
            genres: genreIDs,
            text: text,
            answers: answers,
            sourceMaterialCandidateKeys: sourceMaterialCandidateKeys
        )

        if let minimumRating = answers.minimumRating {
            score += pickForMeMinimumRatingScore(for: item, minimumRating: minimumRating)
        }

        score -= pickForMeRottenTomatoesPenalty(for: item)

        if item.genreIDs.contains(99) && !answers.wantsDocumentary {
            score -= pickForMeDocumentaryDownweight(for: answers)
        }

        score += pickForMeAnimationAdultThemeAdjustment(genres: genreIDs, answers: answers)
        score += pickForMeChildAnimationSettingsAdjustment(item: item, genres: genreIDs, answers: answers)

        score -= pickForMeArchetypeMismatchPenalty(genres: genreIDs, text: text, answers: answers)

        if answers.wantsHistorical && !genreIDs.intersection(pickForMeWarGenreIDs).isEmpty && !answers.wantsWar {
            score -= pickForMeHistoricalWarDownweight(for: answers)
        }

        if shouldPenalizeMissingContentRating(item, answers: answers) {
            score -= 1.5
        }

        score += max(ratingSortValue(for: item), 0) * 0.25

        if library.isInWatchlist(item.key) {
            score += 0.5
        }

        if recommendations.contains(where: { $0.key == item.key }) ||
            moreLikeLastWatched.contains(where: { $0.key == item.key }) ||
            moreLikeFavourite.contains(where: { $0.key == item.key }) {
            score += 0.3
        }

        score += pickForMePersonalizationScore(for: item) * 0.22  // was 0.18 — library signal more important without Groq

        // -- GROQ SCORE BONUSES (disabled with Groq path) --
        // if thematicCandidateKeys.contains(item.key) { score += 20.0 }
        // if let rank = rerankScores[item.key] { score += max(0.0, 16.0 - Double(rank - 1) * 1.5) }
        // -- END GROQ BONUSES --

        return score
    }

    func pickForMePrimaryArchetypeAllows(_ item: MediaItem, answers: PickForMeAnswers) -> Bool {
        guard pickForMeHasDominantPrimaryArchetype(answers) else { return true }
        return pickForMePrimaryArchetypeAlignmentScore(item, answers: answers) >= 3.2
    }

    func pickForMePrimaryArchetypeSoftGateAdjustment(_ alignment: Double, answers: PickForMeAnswers) -> Double {
        guard pickForMeHasDominantPrimaryArchetype(answers) else { return 0 }

        if alignment >= 6.5 {
            return 18.0  // was 14.0
        }

        if alignment >= 4.5 {
            return 8.0   // was 6.0
        }

        if alignment >= 3.2 {
            return -14.0
        }

        return -240.0
    }

    func pickForMePrimaryArchetypeAlignmentScore(_ item: MediaItem, answers: PickForMeAnswers) -> Double {
        let primaryArchetypes = answers.archetypes.filter { archetype in
            !archetype.isAnyOption && archetype != .surprise
        }

        guard !primaryArchetypes.isEmpty else { return 0 }
        return primaryArchetypes.map { pickForMeArchetypeScore(item: item, archetype: $0) }.max() ?? 0
    }

    func pickForMeHasDominantPrimaryArchetype(_ answers: PickForMeAnswers) -> Bool {
        answers.archetypes.contains { archetype in
            !archetype.isAnyOption && archetype != .surprise
        }
    }

    func pickForMeAnswerFulfillmentScore(item: MediaItem, genres: Set<Int>, text: String, answers: PickForMeAnswers, sourceMaterialCandidateKeys: Set<MediaKey>) -> Double {
        var score = 0.0

        for secondaryArchetype in answers.secondaryArchetypes where !secondaryArchetype.isAnyOption {
            let match = pickForMeArchetypeScore(item: item, archetype: secondaryArchetype)
            if match >= 4.0 {
                score += 4.0
            } else if match >= 2.0 {
                score += 1.5
            }
        }

        for genrePreference in answers.genrePreferences where !genrePreference.isAnyOption {
            if pickForMeGenrePreferenceScore(genres: genres, text: text, genrePreference: genrePreference) > 0 {
                score += 2.5
            }
        }

        if let sourceMaterial = answers.sourceMaterial, sourceMaterial != .noPreference {
            if sourceMaterialCandidateKeys.contains(item.key) || pickForMeSourceMaterialTextMatches(text, sourceMaterial: sourceMaterial) {
                score += 5.0
            }
        }

        if let minimumRating = answers.minimumRating, let minimum = minimumRating.minimumRating, ratingSortValue(for: item) >= minimum {
            score += 5.0
        }

        if !answers.contentRatings.isEmpty && !answers.contentRatings.contains(.any) {
            score += 1.0
        }

        if answers.runtimeRange.hasConstraint {
            score += 1.0
        }

        if answers.releaseAge != nil && answers.releaseAge != .noPreference {
            score += 1.0
        }

        return score
    }

    func cachedArchetypeInference(for item: MediaItem) -> ArchetypeInference? {
        guard let detail = detailsCache[item.key], !detail.keywordNames.isEmpty else { return nil }
        if let cached = archetypeInferenceCache[item.key] { return cached }
        let input = ArchetypeInferenceInput(
            genreIDs: item.genreIDs,
            keywordNames: detail.keywordNames,
            networkNames: detail.networkNames,
            numberOfSeasons: detail.seasons.isEmpty ? nil : detail.seasons.count,
            runtime: detail.runtime,
            isInCollection: detail.tmdbCollectionID != nil,
            isTV: item.kind == .tv
        )
        let inference = ArchetypeInferenceEngine.infer(from: input)
        archetypeInferenceCache[item.key] = inference
        return inference
    }

    func pickForMeMinimumRatingScore(for item: MediaItem, minimumRating: PickForMeMinimumRating) -> Double {
        guard let minimum = minimumRating.minimumRating else { return 0 }
        let rating = ratingSortValue(for: item)

        if rating >= minimum {
            return 8.0 + min((rating - minimum) * 4.5, 13.0)
        }

        if rating >= minimum - 0.4 {
            return -12.0
        }

        if rating >= minimum - 0.8 {
            return -28.0
        }

        return -55.0
    }

    func pickForMeRottenTomatoesPenalty(for item: MediaItem) -> Double {
        guard let rt = externalRatingsCache[item.key]?.rottenTomatoesRating else { return 0 }
        if rt < 20 { return 18.0 }
        if rt < 30 { return 12.0 }
        if rt < 40 { return 6.0 }
        if rt < 50 { return 2.5 }
        return 0
    }

    private func shouldPenalizeMissingContentRating(_ item: MediaItem, answers: PickForMeAnswers) -> Bool {
        guard !answers.contentRatings.isEmpty, !answers.contentRatings.contains(.any) else { return false }
        guard let rawRating = detailsCache[item.key]?.ageRating else { return true }
        return rawRating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func pickForMeDocumentaryDownweight(for answers: PickForMeAnswers) -> Double {
        if answers.dealBreakers.contains(.documentary) {
            return 250.0
        }

        if answers.wantsHistorical {
            return 10.0
        }

        if answers.fictionPreference == .nonFiction || answers.fictionPreference == .basedOnTrueStory {
            return 5.0
        }

        return 8.0
    }

    func pickForMeHistoricalWarDownweight(for answers: PickForMeAnswers) -> Double {
        if answers.archetypes.contains(.mission) || answers.secondaryArchetypes.contains(.mission) {
            return 8.0
        }
        return 14.0
    }

    func pickForMeAnimationAdultThemeAdjustment(genres: Set<Int>, answers: PickForMeAnswers) -> Double {
        guard genres.contains(16), answers.prefersAdultLeaningMood, !answers.genrePreferences.contains(.animation) else {
            return 0
        }

        return -2.0
    }

    func pickForMeChildAnimationSettingsAdjustment(item: MediaItem, genres: Set<Int>, answers: PickForMeAnswers) -> Double {
        guard settings.hideLowestAgeRatings, genres.contains(16), !answers.genrePreferences.contains(.animation) else {
            return 0
        }

        let hasFamilyGenre = genres.contains(10751) || genres.contains(10762)
        let hasLowestAgeRating = detailsCache[item.key]?.ageRating.map(Self.isLowestAgeRating) ?? false

        return hasFamilyGenre || hasLowestAgeRating ? -3.0 : 0
    }

    func pickForMePersonalizationScore(for item: MediaItem) -> Double {
        let itemGenres = Set(item.genreIDs)
        guard !itemGenres.isEmpty else { return 0 }

        let highlyRatedItems = library.ratings.compactMap { key, rating in
            rating >= 4 ? library.items[key] : nil
        }

        let favouriteScore = pickForMeGenreOverlapScore(itemGenres: itemGenres, sourceItems: library.favouriteItems, weight: 0.85, cap: 3.4)
        let highlyRatedScore = pickForMeGenreOverlapScore(itemGenres: itemGenres, sourceItems: highlyRatedItems, weight: 0.7, cap: 3.0)
        let watchedScore = pickForMeGenreOverlapScore(itemGenres: itemGenres, sourceItems: library.watchedItems, weight: 0.22, cap: 2.0)
        return favouriteScore + highlyRatedScore + watchedScore
    }

    func pickForMeGenreOverlapScore(itemGenres: Set<Int>, sourceItems: [MediaItem], weight: Double, cap: Double) -> Double {
        let overlapCount = sourceItems.uniqued().reduce(0) { partialResult, other in
            partialResult + (itemGenres.isDisjoint(with: Set(other.genreIDs)) ? 0 : 1)
        }

        return min(Double(overlapCount) * weight, cap)
    }


}
