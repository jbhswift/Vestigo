import SwiftUI
import Foundation

// MARK: - WatchedSortOption

private enum WatchedSortOption: String, CaseIterable, Identifiable {
    case rating, release, watched
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rating: return "Rating"
        case .release: return "Released"
        case .watched: return "Watched"
        }
    }
}

// MARK: - WatchedLibraryView

struct WatchedLibraryView: View {
    @ObservedObject var model: VestigoModel
    @State private var filter: MediaFilter = .both
    @State private var sort: WatchedSortOption = .watched
    @State private var sortDirection: SortDirection = .descending

    private var filteredItems: [MediaItem] {
        var items = model.library.watchedItems
        switch filter {
        case .movie: items = items.filter { $0.kind == .movie }
        case .tv: items = items.filter { $0.kind == .tv }
        case .both: break
        }
        return sortedItems(items)
    }

    private func sortedItems(_ items: [MediaItem]) -> [MediaItem] {
        let dates = model.library.watchedDates
        let source = model.settings.preferredRatingSource
        let external = model.externalRatingsCache

        let result = items.sorted { a, b in
            switch sort {
            case .rating:
                func rating(_ item: MediaItem) -> Double {
                    if source == .imdb, let v = external[item.key]?.imdbRating { return v }
                    return item.voteAverage
                }
                let av = rating(a), bv = rating(b)
                if av != bv { return av > bv }
            case .release:
                let av = a.releaseDateValue ?? .distantPast
                let bv = b.releaseDateValue ?? .distantPast
                if av != bv { return av > bv }
            case .watched:
                let av = dates[a.key] ?? .distantPast
                let bv = dates[b.key] ?? .distantPast
                if av != bv { return av > bv }
            }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
        return sortDirection == .ascending ? result.reversed() : result
    }

    var body: some View {
        BaseScreen(title: "Watched", filter: $filter, settings: model.settings) {
            VStack(spacing: 14) {
                HStack(spacing: 8) {
                    FilterPills(filter: $filter, options: [.movie, .tv, .both]) {}
                    Text("\(filteredItems.count)")
                        .font(.caption2.bold())
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .padding(.horizontal, 7)
                        .frame(maxHeight: .infinity)
                        .liquidGlass(cornerRadius: 100)
                }

                SortRow(direction: $sortDirection) {
                    Picker("Sort", selection: $sort) {
                        ForEach(WatchedSortOption.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .liquidGlass(cornerRadius: 18)
                }

                if filteredItems.isEmpty {
                    StatusBubble(title: "Nothing watched yet", text: "Items you mark as watched will appear here.")
                } else {
                    MediaGridOrList(items: filteredItems, hideWatchedForUpcoming: false, model: model)
                }
            }
        }
    }
}
