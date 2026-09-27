import Foundation

enum HomeDisplayCarousel: String, Codable, CaseIterable, Identifiable, Hashable {
    case trending
    case forYou
    case moreLikeLast
    case moreLikeFavourite
    case watchlistPicks
    case seriesNext
    case newReleases
    case upcoming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trending: return "Trending now"
        case .forYou: return "For you"
        case .moreLikeLast: return "More like recent watched"
        case .moreLikeFavourite: return "More like a favourite"
        case .watchlistPicks: return "From your watchlist"
        case .seriesNext: return "Continue with related series"
        case .newReleases: return "New releases"
        case .upcoming: return "Upcoming releases"
        }
    }

    init(homeCarousel: HomeCarousel) {
        switch homeCarousel {
        case .trending:
            self = .trending
        case .recommendations:
            self = .forYou
        case .newReleases:
            self = .newReleases
        case .upcoming:
            self = .upcoming
        }
    }

    init(recommendationCarousel: RecommendationCarousel) {
        switch recommendationCarousel {
        case .personalized:
            self = .forYou
        case .moreLikeLast:
            self = .moreLikeLast
        case .moreLikeFavourite:
            self = .moreLikeFavourite
        case .watchlistPicks:
            self = .watchlistPicks
        case .seriesNext:
            self = .seriesNext
        }
    }
}
