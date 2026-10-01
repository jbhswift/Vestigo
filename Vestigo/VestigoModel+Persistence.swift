import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

extension VestigoModel {

    func loadLocal() {
        library = Storage.load(UserLibrary.self, key: "Vestigo.library") ?? UserLibrary()
        settings = Storage.load(AppSettings.self, key: "Vestigo.settings") ?? AppSettings()
        externalRatingsCache = Storage.load([MediaKey: ExternalRatings].self, key: "Vestigo.externalRatings") ?? [:]
        calendarEventIDs = Storage.load([MediaKey: String].self, key: "Vestigo.calendarEventIDs") ?? [:]
        describeItResultsCache = Storage.load([String: [ThematicSearchResult]].self, key: "Vestigo.describeItCache") ?? [:]
        providerCache = Storage.load([MediaKey: [StreamingOption]].self, key: "Vestigo.providerCache") ?? [:]

        // Stamp any watched items that predate date tracking with today's date (idempotent).
        for key in library.watched { library.setWatchedDateIfUnset(for: key) }

        searchFilter = settings.defaultSearchFilter
        mediaFilter = settings.defaultHomeFilter

        // Ensure .recommendations appears before .newReleases (migration for existing installs)
        if let recIdx = settings.homeCarouselOrder.firstIndex(of: .recommendations),
           let newRelIdx = settings.homeCarouselOrder.firstIndex(of: .newReleases),
           recIdx > newRelIdx {
            settings.homeCarouselOrder.remove(at: recIdx)
            let insertAt = settings.homeCarouselOrder.firstIndex(of: .newReleases) ?? min(1, settings.homeCarouselOrder.count)
            settings.homeCarouselOrder.insert(.recommendations, at: insertAt)
        }

        // Ensure all recommendation sub-carousels are hidden by default for existing installs
        let subCarousels: Set<RecommendationCarousel> = [.moreLikeLast, .moreLikeFavourite, .watchlistPicks, .seriesNext]
        if settings.recommendationCarouselHidden.isDisjoint(with: subCarousels) {
            settings.recommendationCarouselHidden.formUnion(subCarousels)
        }

        // Same migration for the unified home carousel list.
        let displaySubCarousels: Set<HomeDisplayCarousel> = [.moreLikeLast, .moreLikeFavourite, .watchlistPicks, .seriesNext]
        if settings.homeDisplayCarouselHidden.isDisjoint(with: displaySubCarousels) {
            settings.homeDisplayCarouselHidden.formUnion(displaySubCarousels)
        }
    }

    func syncFromCloudOnLaunch() async {
        guard let snapshot = Storage.loadKVSnapshot() else {
            saveLocalSoon()
            return
        }

        let localModifiedAt = Storage.load(Date.self, key: "Vestigo.localSnapshotModifiedAt") ?? .distantPast
        guard snapshot.modifiedAt > localModifiedAt else {
            if localModifiedAt > snapshot.modifiedAt {
                saveLocalSoon()
            }
            return
        }

        applyKVSnapshot(snapshot)
        Storage.save(snapshot.modifiedAt, key: "Vestigo.localSnapshotModifiedAt")
    }

    func handleExternalKVChange() {
        guard let snapshot = Storage.loadKVSnapshot() else { return }
        let localModifiedAt = Storage.load(Date.self, key: "Vestigo.localSnapshotModifiedAt") ?? .distantPast
        guard snapshot.modifiedAt > localModifiedAt else { return }
        applyKVSnapshot(snapshot)
        Storage.save(snapshot.modifiedAt, key: "Vestigo.localSnapshotModifiedAt")
    }

    func offerStreamingSetupIfNeeded() {
        if !settings.hasSeenStreamingSetup {
            showStreamingSetup = true
        }
    }

    func offerTourIfNeeded() {
        if !UserDefaults.standard.bool(forKey: "Vestigo.hasSeenTour") {
            showTour = true
        }
    }

    func replayTour() {
        UserDefaults.standard.set(false, forKey: "Vestigo.hasSeenTour")
        showTour = true
    }

    func completeStreamingSetup() {
        settings.hasSeenStreamingSetup = true
        showStreamingSetup = false
        saveLocalSoon()
    }

    func toggleSubscribedService(_ serviceID: String) {
        if settings.subscribedServiceNames.contains(serviceID) {
            settings.subscribedServiceNames.remove(serviceID)
        } else {
            settings.subscribedServiceNames.insert(serviceID)
        }
        saveLocalSoon()
    }

    func saveSettings() {
        saveLocalSoon()
        scheduleBackendLibraryPush()
    }

    func loadStreamingServiceCatalog() async {
        async let motnLoad: Void = loadRegionServiceCatalog()
        async let tmdbLoad: Void = loadTMDbRegionProviders()
        _ = await (motnLoad, tmdbLoad)
    }

    func loadRegionServiceCatalog() async {
        let region = settings.streamingRegion.rawValue
        guard regionServiceCatalogsByRegion[region] == nil else { return }
        do {
            regionServiceCatalogsByRegion[region] = try await streamingCatalog.services(forRegion: region)
        } catch { }
    }

    func loadAllRegionServiceCatalogs() async {
        for region in StreamingRegion.allCases.map(\.rawValue) {
            guard regionServiceCatalogsByRegion[region] == nil else { continue }
            do {
                regionServiceCatalogsByRegion[region] = try await streamingCatalog.services(forRegion: region)
            } catch { }
        }
    }

    func loadTMDbRegionProviders() async {
        let region = settings.streamingRegion.rawValue
        guard tmdbProvidersByRegion[region] == nil else { return }
        do {
            tmdbProvidersByRegion[region] = try await tmdb.watchProviders(regionCode: region)
        } catch { }
    }

    func loadTMDbGlobalProviders() async {
        guard tmdbGlobalProviders.isEmpty else { return }
        do {
            tmdbGlobalProviders = try await tmdb.watchProviders()
        } catch { }
    }

    var providerCatalogCacheCount: Int {
        regionServiceCatalogsByRegion.values.reduce(0) { $0 + $1.count }
            + tmdbProvidersByRegion.values.reduce(0) { $0 + $1.count }
            + tmdbGlobalProviders.count
    }

    func clearProviderCatalogCaches() {
        regionServiceCatalogsByRegion = [:]
        tmdbProvidersByRegion = [:]
        tmdbGlobalProviders = []
    }

    func saveLocalSoon() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 150_000_000)
            await MainActor.run { self?.saveLocal() }
        }
    }

    func saveLocal() {
        Storage.save(library, key: "Vestigo.library")
        Storage.save(settings, key: "Vestigo.settings")
        Storage.save(externalRatingsCache, key: "Vestigo.externalRatings")
        Storage.save(calendarEventIDs, key: "Vestigo.calendarEventIDs")
        Storage.save(describeItResultsCache.filter { !$0.value.isEmpty }, key: "Vestigo.describeItCache")
        let watchmodeOnly = providerCache.filter { !tmdbFallbackKeys.contains($0.key) }
        Storage.save(watchmodeOnly, key: "Vestigo.providerCache")

        guard !isApplyingCloudSnapshot else { return }

        Storage.saveKVSnapshot(library: library, settings: settings)
    }

    func applyKVSnapshot(_ snapshot: KVLibrarySnapshot) {
        guard !isApplyingCloudSnapshot else { return }
        isApplyingCloudSnapshot = true
        defer { isApplyingCloudSnapshot = false }
        library = snapshot.library
        settings = snapshot.settings
        searchFilter = settings.defaultSearchFilter
        mediaFilter = settings.defaultHomeFilter
        saveLocal()
    }

    func loadFriendsCache() {
        guard let data = try? Data(contentsOf: friendsCacheURL),
              let cached = try? JSONDecoder().decode([FriendProfile].self, from: data),
              !cached.isEmpty else { return }
        friends = cached
    }

    func saveFriendsCache() {
        guard !friends.isEmpty,
              let data = try? JSONEncoder().encode(friends) else { return }
        try? data.write(to: friendsCacheURL, options: .atomic)
    }

    func clearFriendsCache() {
        try? FileManager.default.removeItem(at: friendsCacheURL)
    }

}
