import SwiftUI
import Foundation

extension VestigoModel {

    func scheduleRecommendationsRefresh() {
        recommendationsRefreshTask?.cancel()
        recommendationsRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.loadSmartRecommendations()
        }
    }

    func savePickForMeRecentSearch(_ answers: PickForMeAnswers) {
        let recent = PickForMeRecentSearch(date: Date(), answers: answers)
        var searches = settings.pickForMeRecentSearches
        searches.removeAll { $0.answers.summaryTags == recent.answers.summaryTags }
        searches.insert(recent, at: 0)
        if searches.count > 10 { searches = Array(searches.prefix(10)) }
        settings.pickForMeRecentSearches = searches
        saveLocalSoon()
    }

    func saveDescribeItRecentSearch(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var searches = settings.describeItRecentSearches
        searches.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        searches.insert(trimmed, at: 0)
        settings.describeItRecentSearches = Array(searches.prefix(10))
        saveLocalSoon()
    }

    func removePickForMeRecentSearch(_ search: PickForMeRecentSearch) {
        settings.pickForMeRecentSearches.removeAll { $0.id == search.id }
        saveLocalSoon()
    }

    func removeDescribeItRecentSearch(_ query: String) {
        settings.describeItRecentSearches.removeAll { $0.caseInsensitiveCompare(query) == .orderedSame }
        saveLocalSoon()
    }

    func thematicSearch(query: String, filter: MediaFilter) async throws -> [ThematicSearchResult] {
        let service = ThematicSearchService(tmdb: tmdb)
        return try await service.search(rawQuery: query, filter: filter)
    }

}
