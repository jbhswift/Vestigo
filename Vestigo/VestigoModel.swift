import SwiftUI
import Foundation
import Combine
#if canImport(FoundationModels)
import FoundationModels
#endif

struct PendingFriendAdd: Equatable {
    let id: String
    let name: String
}

@MainActor
final class VestigoModel: ObservableObject {
    @Published var selectedTab: AppTab = .home {
        didSet { AnalyticsService.shared.track(.tabViewed(selectedTab)) }
    }
    @Published var tabTransitionDirection: TabTransitionDirection = .forward
    @Published var mediaFilter: MediaFilter = .both
    @Published var homeViewMode: ViewMode = .tile
    @Published var searchViewMode: ViewMode = .tile
    @Published var watchlistViewMode: ViewMode = .tile
    @Published var collectionViewMode: ViewMode = .tile
    @Published var sortOption: SortOption = .tmdbRating
    @Published var sortDirection: SortDirection = .descending

    @Published var searchFiltersExpanded = false
    @Published var expandedSearchFilterSections: Set<SearchFilterSection> = []
    @Published var selectedRuntimeFilters: Set<SearchRuntimeFilter> = []
    @Published var selectedDateFilters: Set<SearchDateFilter> = []
    @Published var minimumTMDbRatingFilter: SearchRatingFilter?
    @Published var searchText = ""
    @Published var searchFilter: SearchFilter = .all
    @Published var searchFieldIsFocused = false
    @Published var trending: [MediaItem] = []
    @Published var popular: [MediaItem] = []
    @Published var newReleases: [MediaItem] = []
    @Published var upcoming: [MediaItem] = []
    @Published var topRatedMovies: [MediaItem] = []
    @Published var topRatedShows: [MediaItem] = []
    @Published var recommendations: [MediaItem] = []
    @Published var moreLikeLastWatched: [MediaItem] = []
    @Published var moreLikeFavourite: [MediaItem] = []
    @Published var fromTopGenre: [MediaItem] = []
    @Published var trySomethingNewRecommendations: [MediaItem] = []
    @Published var seriesNext: [MediaItem] = []
    @Published var searchResults: [MediaItem] = []
    @Published var searchPeopleResults: [PersonSummary] = []
    @Published var genreResults: [String: [MediaItem]] = [:]
    @Published var detailsCache: [MediaKey: MediaDetail] = [:]
    @Published var externalRatingsCache: [MediaKey: ExternalRatings] = [:]
    @Published var providerCache: [MediaKey: [StreamingOption]] = [:]
    @Published var tmdbFallbackKeys: Set<MediaKey> = []
    var watchmodeBackgroundRetried: Set<MediaKey> = []
    var describeItResultsCache: [String: [ThematicSearchResult]] = [:]

    @Published var relatedMediaCache: [MediaKey: [RelatedMediaSection]] = [:]
    @Published var personCreditsCache: [Int: PersonCreditBundle] = [:]
    @Published var personDetails: [Int: PersonDetail] = [:]
    var archetypeInferenceCache: [MediaKey: ArchetypeInference] = [:]
    @Published var collectionRecommendations: [UUID: [MediaItem]] = [:]
    @Published var pendingRatingPromptItem: MediaItem?
    @Published var pendingRatingPromptValue: Double = 0
    @Published var pendingRatingPromptDate: Date? = nil
    @Published var pendingRatingPromptMakeFavourite = false
    @Published var pendingRatingPromptRestoreWatchlist = false

    @Published var library = UserLibrary()
    @Published var settings = AppSettings()
    @Published var selectedItem: MediaItem? {
        didSet { if let item = selectedItem { recordRecentlyViewed(item) } }
    }
    @Published var selectedPerson: PersonSummary?
    @Published var homePath: [HomeRoute] = []
    @Published var searchPath: [SearchRoute] = []
    @Published var isLoading = false
    @Published var errorText: String?
    @Published var exportDocument = ExportDocument(text: "")
    @Published var exportFormat: ExportFormat = .text
    @Published var showExporter = false
    @Published var pendingFavouriteReplacement: MediaItem?
    @Published var showFavouriteReplacementAlert = false
    @Published var friendDetailContext: FriendProfile? = nil
    @Published var friendsResetToken = UUID()
    @Published var watchlistResetToken = UUID()
    @Published var collectionsResetToken = UUID()
    @Published var imageRefreshToken = 0
    @Published var showStreamingSetup = false
    @Published var calendarEventIDs: [MediaKey: String] = [:]
    @Published var showOMDbLimitAlert = false
    @Published var friends: [FriendProfile] = []
    @Published var friendsLoading = false
    @Published var friendsDiagnostic: String = ""
    @Published var publishDiagnostic: String = ""
    @Published var pendingFriendAdd: PendingFriendAdd? = nil
    @Published var pendingRemovalNames: [String] = []
    @Published var userAvatarData: Data? = nil
    @Published var linkLog: [String] = []
    var lastIncomingCheck: Date = .distantPast

    let tmdb = TMDbService()
    // TasteDive is intentionally disabled because the current recommendation system no longer calls it.
    // Keep this wiring nearby in case we decide to re-evaluate TasteDive as a future supplemental source.
    // private let tasteDive = TasteDiveService()
    let streaming = StreamingAvailabilityService()
    let relatedMedia = RelatedMediaService()
    let backend = VestigoBackendClient()
    let releaseCalendar = ReleaseCalendarService()
    let publicSync = CloudPublicSyncService()
    let externalRatingBatchLimit = 8
    var externalRatingEmptyRefreshes: Set<MediaKey> = []
    var externalRatingInFlight: Set<MediaKey> = []
    var searchTask: Task<Void, Never>?
    var saveTask: Task<Void, Never>?
    var recommendationsRefreshTask: Task<Void, Never>?
    var publishTask: Task<Void, Never>?
    var searchRequestID = UUID()
    var isApplyingCloudSnapshot = false
    var mediaSearchCache: [String: [MediaItem]] = [:]
    var peopleSearchCache: [String: [PersonSummary]] = [:]
    // Disabled with TasteDiveService; no active path should credit or query TasteDive right now.
    // private var tasteDiveSimilarCache: [MediaKey: [MediaItem]] = [:]
    var tmdbExpandedSimilarCache: [MediaKey: [MediaItem]] = [:]
    var franchiseRecommendationCache: [MediaKey: [MediaItem]] = [:]
    var pickForMeThematicCache: [String: [MediaItem]] = [:]

    // In-memory session state — survives tab switches but not app quit
    var pickForMeSessionAnswers: PickForMeAnswers? = nil
    var pickForMeSessionResults: [MediaItem] = []

    // MARK: - File URLs (used by extension files)

    var friendsCacheURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("vestigo-friends-cache.json")
    }

    var avatarFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("vestigo-user-avatar.jpg")
    }

    // MARK: - Small helpers

    func logLink(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let entry = "[\(formatter.string(from: Date()))] \(message)"
        linkLog.append(entry)
        if linkLog.count > 30 { linkLog.removeFirst() }
    }

    var myInviteURL: String {
        var url = "https://jbhswift.github.io/friend?id=\(settings.socialInviteID)"
        if !settings.socialMyRecordName.isEmpty {
            url += "&rid=\(settings.socialMyRecordName)"
        }
        if !settings.name.isEmpty, let encoded = settings.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            url += "&name=\(encoded)"
        }
        return url
    }

    struct HomeSectionLoadResult {
        let section: HomeSectionKind
        let items: [MediaItem]
        let errorText: String?
    }
}
