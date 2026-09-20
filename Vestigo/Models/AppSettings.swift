import SwiftUI

struct AppSettings: Codable, Hashable {
    var recommendationStrength: Double = 3.5
    var appearance: AppearanceMode = .dark
    var accent: AccentChoice = .blue
    var accentRed: Double = 0.20
    var accentGreen: Double = 0.44
    var accentBlue: Double = 1.00
    var name: String = ""
    var prioritiseEnglish: Bool = true
    var removeItemsFromWatchlist: Bool = false
    var usePlainBackground: Bool = false
    var hideAdultResults: Bool = false
    var hideAnimeResults: Bool = false
    var hideLowestAgeRatings: Bool = false
    var hideWatchedFromHome: Bool = false
    var hideWatchedFromSearch: Bool = false
    var hideShortFilmsFromHome = false
    var hideShortFilmsFromSearch = false
    var hideShortFilmsFromRecommended = false
    var hideShortFilmsFromCollectionRecommendations = false
    var hideExtrasAndPromosFromHome = false
    var hideExtrasAndPromosFromSearch = false
    var hideExtrasAndPromosFromRecommended = false
    var hideExtrasAndPromosFromCollectionRecommendations = false
    var defaultSearchFilter: SearchFilter = .all
    var defaultHomeFilter: MediaFilter = .both
    var defaultCategorySort: GenreSort = .tmdbRating
    var showUpcomingReleases: Bool = true
    var hideUpcomingFromSearch = false
    var hideUpcomingFromRecommended = false
    var hideUpcomingFromCollectionRecommendations = false
    var warnBeforeReplacingFavourite = true
    var promptToRateAfterMarkingWatched = true
    var autoTrackWatchDate: Bool = false
    var preferredRatingSource: RatingSource = .imdb
    var homeCarouselOrder: [HomeCarousel] = [.trending, .recommendations, .newReleases, .upcoming]
    var homeCarouselHidden: Set<HomeCarousel> = []
    var socialShareWatchlist: Bool = false
    var socialShareWatched: Bool = false
    var socialDontShare: Bool = true
    var socialFeaturedItemKeys: [String] = []
    var socialExcitedForKeys: [String] = []
    var socialInviteID: String = UUID().uuidString
    var socialConfirmedFriendIDs: [String] = []
    var socialProcessedRequestIDs: [String] = []
    var socialProcessedRemovalIDs: [String] = []
    var socialMyRecordName: String = ""
    var recommendationCarouselOrder: [RecommendationCarousel] = RecommendationCarousel.allCases
    var recommendationCarouselHidden: Set<RecommendationCarousel> = [.moreLikeLast, .moreLikeFavourite, .watchlistPicks, .seriesNext]
    var omdbPrimaryKey: String = ""
    var omdbTierLimit: Int = 1_000
    var omdbDailyRequestCount: Int = 0
    var omdbTotalRequestCount: Int = 0
    var omdbLastRequestDate: String = ""
    var subscribedServiceNames: Set<String> = []
    var hasSeenStreamingSetup: Bool = false
    var streamingRegion: StreamingRegion = .us
    var pickForMeRecentSearches: [PickForMeRecentSearch] = []
    var describeItRecentSearches: [String] = []
    var recentlyViewedItems: [MediaItem] = []
    var socialExcitedForItemCache: [MediaItem] = []
    var ratingSourceIMDbDefaultApplied: Bool = false
    enum CodingKeys: String, CodingKey {
        case recommendationStrength
        case appearance
        case accent
        case accentRed
        case accentGreen
        case accentBlue
        case name
        case prioritiseEnglish
        case removeItemsFromWatchlist
        case usePlainBackground
        case hideAdultResults
        case hideAnimeResults
        case hideLowestAgeRatings
        case hideWatchedFromHome
        case hideWatchedFromSearch
        case hideShortFilmsFromHome
        case hideShortFilmsFromSearch
        case hideShortFilmsFromRecommended
        case hideShortFilmsFromCollectionRecommendations
        case hideExtrasAndPromosFromHome
        case hideExtrasAndPromosFromSearch
        case hideExtrasAndPromosFromRecommended
        case hideExtrasAndPromosFromCollectionRecommendations
        case defaultSearchFilter
        case defaultHomeFilter
        case defaultCategorySort
        case showUpcomingReleases
        case hideUpcomingFromSearch
        case hideUpcomingFromRecommended
        case hideUpcomingFromCollectionRecommendations
        case warnBeforeReplacingFavourite
        case promptToRateAfterMarkingWatched
        case autoTrackWatchDate
        case preferredRatingSource
        case homeCarouselOrder
        case homeCarouselHidden
        case recommendationCarouselOrder = "forYouCarouselOrder"
        case recommendationCarouselHidden = "forYouCarouselHidden"
        case omdbPrimaryKey
        case omdbTierLimit
        case omdbDailyRequestCount
        case omdbTotalRequestCount
        case omdbLastRequestDate
        case subscribedServiceNames
        case hasSeenStreamingSetup
        case streamingRegion
        case pickForMeRecentSearches
        case describeItRecentSearches
        case socialShareWatchlist
        case socialShareWatched
        case socialDontShare
        case socialFeaturedItemKeys
        case socialExcitedForKeys
        case socialInviteID
        case socialConfirmedFriendIDs
        case socialProcessedRequestIDs
        case socialProcessedRemovalIDs
        case socialMyRecordName
        case recentlyViewedItems
        case socialExcitedForItemCache
        case ratingSourceIMDbDefaultApplied
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        recommendationStrength = try container.decodeIfPresent(Double.self, forKey: .recommendationStrength) ?? recommendationStrength
        appearance = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? appearance
        accent = try container.decodeIfPresent(AccentChoice.self, forKey: .accent) ?? accent
        accentRed = try container.decodeIfPresent(Double.self, forKey: .accentRed) ?? accentRed
        accentGreen = try container.decodeIfPresent(Double.self, forKey: .accentGreen) ?? accentGreen
        accentBlue = try container.decodeIfPresent(Double.self, forKey: .accentBlue) ?? accentBlue
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? name
        prioritiseEnglish = try container.decodeIfPresent(Bool.self, forKey: .prioritiseEnglish) ?? prioritiseEnglish
        removeItemsFromWatchlist = try container.decodeIfPresent(Bool.self, forKey: .removeItemsFromWatchlist) ?? removeItemsFromWatchlist
        usePlainBackground = try container.decodeIfPresent(Bool.self, forKey: .usePlainBackground) ?? usePlainBackground
        hideAdultResults = try container.decodeIfPresent(Bool.self, forKey: .hideAdultResults) ?? hideAdultResults
        hideAnimeResults = try container.decodeIfPresent(Bool.self, forKey: .hideAnimeResults) ?? hideAnimeResults
        hideLowestAgeRatings = try container.decodeIfPresent(Bool.self, forKey: .hideLowestAgeRatings) ?? hideLowestAgeRatings
        hideWatchedFromHome = try container.decodeIfPresent(Bool.self, forKey: .hideWatchedFromHome) ?? hideWatchedFromHome
        hideWatchedFromSearch = try container.decodeIfPresent(Bool.self, forKey: .hideWatchedFromSearch) ?? hideWatchedFromSearch
        hideShortFilmsFromHome = try container.decodeIfPresent(Bool.self, forKey: .hideShortFilmsFromHome) ?? hideShortFilmsFromHome
        hideShortFilmsFromSearch = try container.decodeIfPresent(Bool.self, forKey: .hideShortFilmsFromSearch) ?? hideShortFilmsFromSearch
        hideShortFilmsFromRecommended = try container.decodeIfPresent(Bool.self, forKey: .hideShortFilmsFromRecommended) ?? hideShortFilmsFromRecommended
        hideShortFilmsFromCollectionRecommendations = try container.decodeIfPresent(Bool.self, forKey: .hideShortFilmsFromCollectionRecommendations) ?? hideShortFilmsFromCollectionRecommendations
        hideExtrasAndPromosFromHome = try container.decodeIfPresent(Bool.self, forKey: .hideExtrasAndPromosFromHome) ?? hideExtrasAndPromosFromHome
        hideExtrasAndPromosFromSearch = try container.decodeIfPresent(Bool.self, forKey: .hideExtrasAndPromosFromSearch) ?? hideExtrasAndPromosFromSearch
        hideExtrasAndPromosFromRecommended = try container.decodeIfPresent(Bool.self, forKey: .hideExtrasAndPromosFromRecommended) ?? hideExtrasAndPromosFromRecommended
        hideExtrasAndPromosFromCollectionRecommendations = try container.decodeIfPresent(Bool.self, forKey: .hideExtrasAndPromosFromCollectionRecommendations) ?? hideExtrasAndPromosFromCollectionRecommendations
        defaultSearchFilter = try container.decodeIfPresent(SearchFilter.self, forKey: .defaultSearchFilter) ?? defaultSearchFilter
        defaultHomeFilter = try container.decodeIfPresent(MediaFilter.self, forKey: .defaultHomeFilter) ?? defaultHomeFilter
        defaultCategorySort = try container.decodeIfPresent(GenreSort.self, forKey: .defaultCategorySort) ?? defaultCategorySort
        showUpcomingReleases = try container.decodeIfPresent(Bool.self, forKey: .showUpcomingReleases) ?? showUpcomingReleases
        hideUpcomingFromSearch = try container.decodeIfPresent(Bool.self, forKey: .hideUpcomingFromSearch) ?? hideUpcomingFromSearch
        hideUpcomingFromRecommended = try container.decodeIfPresent(Bool.self, forKey: .hideUpcomingFromRecommended) ?? hideUpcomingFromRecommended
        hideUpcomingFromCollectionRecommendations = try container.decodeIfPresent(Bool.self, forKey: .hideUpcomingFromCollectionRecommendations) ?? hideUpcomingFromCollectionRecommendations
        warnBeforeReplacingFavourite = try container.decodeIfPresent(Bool.self, forKey: .warnBeforeReplacingFavourite) ?? warnBeforeReplacingFavourite
        promptToRateAfterMarkingWatched = try container.decodeIfPresent(Bool.self, forKey: .promptToRateAfterMarkingWatched) ?? promptToRateAfterMarkingWatched
        autoTrackWatchDate = try container.decodeIfPresent(Bool.self, forKey: .autoTrackWatchDate) ?? autoTrackWatchDate
        let ratingSourceAlreadyMigrated = (try? container.decodeIfPresent(Bool.self, forKey: .ratingSourceIMDbDefaultApplied)) ?? false
        if ratingSourceAlreadyMigrated {
            preferredRatingSource = try container.decodeIfPresent(RatingSource.self, forKey: .preferredRatingSource) ?? preferredRatingSource
        }
        // else: no stored migration flag → first load of this version, keep the .imdb default regardless of any previously saved value
        ratingSourceIMDbDefaultApplied = true

        let savedHomeOrder = try container.decodeIfPresent([HomeCarousel].self, forKey: .homeCarouselOrder) ?? []
        let intendedHomeOrder: [HomeCarousel] = [.trending, .recommendations, .newReleases, .upcoming]
        var mergedHomeOrder = Self.mergedOrder(saved: savedHomeOrder, defaults: intendedHomeOrder)
        // Migration: if upgrading from a saved order without .recommendations, insert it at position 1
        if !savedHomeOrder.contains(.recommendations) {
            mergedHomeOrder.removeAll { $0 == .recommendations }
            mergedHomeOrder.insert(.recommendations, at: min(1, mergedHomeOrder.count))
        }
        homeCarouselOrder = mergedHomeOrder
        homeCarouselHidden = try container.decodeIfPresent(Set<HomeCarousel>.self, forKey: .homeCarouselHidden) ?? homeCarouselHidden

        let savedRecOrder = ((try? container.decodeIfPresent([String].self, forKey: .recommendationCarouselOrder)) ?? [])
            .compactMap(RecommendationCarousel.init(rawValue:))
        recommendationCarouselOrder = Self.mergedOrder(saved: savedRecOrder, defaults: RecommendationCarousel.allCases)
        let savedRecHidden = ((try? container.decodeIfPresent([String].self, forKey: .recommendationCarouselHidden)) ?? [])
            .compactMap(RecommendationCarousel.init(rawValue:))
        recommendationCarouselHidden = savedRecHidden.isEmpty ? recommendationCarouselHidden : Set(savedRecHidden)
        omdbPrimaryKey = try container.decodeIfPresent(String.self, forKey: .omdbPrimaryKey) ?? omdbPrimaryKey
        omdbTierLimit = try container.decodeIfPresent(Int.self, forKey: .omdbTierLimit) ?? omdbTierLimit
        omdbDailyRequestCount = try container.decodeIfPresent(Int.self, forKey: .omdbDailyRequestCount) ?? omdbDailyRequestCount
        omdbTotalRequestCount = try container.decodeIfPresent(Int.self, forKey: .omdbTotalRequestCount) ?? omdbTotalRequestCount
        omdbLastRequestDate = try container.decodeIfPresent(String.self, forKey: .omdbLastRequestDate) ?? omdbLastRequestDate
        subscribedServiceNames = try container.decodeIfPresent(Set<String>.self, forKey: .subscribedServiceNames) ?? subscribedServiceNames
        hasSeenStreamingSetup = try container.decodeIfPresent(Bool.self, forKey: .hasSeenStreamingSetup) ?? hasSeenStreamingSetup
        streamingRegion = try container.decodeIfPresent(StreamingRegion.self, forKey: .streamingRegion) ?? streamingRegion
        pickForMeRecentSearches = try container.decodeIfPresent([PickForMeRecentSearch].self, forKey: .pickForMeRecentSearches) ?? pickForMeRecentSearches
        describeItRecentSearches = try container.decodeIfPresent([String].self, forKey: .describeItRecentSearches) ?? describeItRecentSearches
        socialShareWatchlist = try container.decodeIfPresent(Bool.self, forKey: .socialShareWatchlist) ?? socialShareWatchlist
        socialShareWatched = try container.decodeIfPresent(Bool.self, forKey: .socialShareWatched) ?? socialShareWatched
        socialDontShare = try container.decodeIfPresent(Bool.self, forKey: .socialDontShare) ?? socialDontShare
        socialFeaturedItemKeys = try container.decodeIfPresent([String].self, forKey: .socialFeaturedItemKeys) ?? socialFeaturedItemKeys
        socialExcitedForKeys = try container.decodeIfPresent([String].self, forKey: .socialExcitedForKeys) ?? socialExcitedForKeys
        let storedInviteID = try container.decodeIfPresent(String.self, forKey: .socialInviteID) ?? ""
        socialInviteID = storedInviteID.isEmpty ? UUID().uuidString : storedInviteID
        socialConfirmedFriendIDs = try container.decodeIfPresent([String].self, forKey: .socialConfirmedFriendIDs) ?? socialConfirmedFriendIDs
        socialProcessedRequestIDs = try container.decodeIfPresent([String].self, forKey: .socialProcessedRequestIDs) ?? socialProcessedRequestIDs
        socialProcessedRemovalIDs = try container.decodeIfPresent([String].self, forKey: .socialProcessedRemovalIDs) ?? socialProcessedRemovalIDs
        socialMyRecordName = try container.decodeIfPresent(String.self, forKey: .socialMyRecordName) ?? socialMyRecordName
        recentlyViewedItems = try container.decodeIfPresent([MediaItem].self, forKey: .recentlyViewedItems) ?? recentlyViewedItems
        socialExcitedForItemCache = try container.decodeIfPresent([MediaItem].self, forKey: .socialExcitedForItemCache) ?? socialExcitedForItemCache
    }

    private static func mergedOrder<T: Hashable>(saved: [T], defaults: [T]) -> [T] {
        let known = Set(defaults)
        var result = saved.filter { known.contains($0) }
        let present = Set(result)
        result.append(contentsOf: defaults.filter { !present.contains($0) })
        return result
    }
}

extension AppSettings {
    var accentColor: Color {
        Color(red: accentRed, green: accentGreen, blue: accentBlue)
    }

    mutating func setAccentColor(_ color: Color) {
#if canImport(UIKit)
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha)

        accentRed = Double(red)
        accentGreen = Double(green)
        accentBlue = Double(blue)
#else
        accentRed = 0.20
        accentGreen = 0.44
        accentBlue = 1.00
#endif
    }
}
