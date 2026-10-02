import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Pushes the user's own library data to the backend for friends to read, and keeps the
/// server's sharing_prefs in sync with the local toggles. Replaces the old
/// `schedulePublicProfilePublish`/`publishPublicProfile` (CloudKit), removed in Stage 6.
///
/// Category mapping deliberately mirrors the old 2-toggle UI (watchlist, watched) even
/// though the backend schema has 4 independent categories: ratings and currently-watching
/// ride along with the "watched" toggle, exactly like the old CloudKit payload bundled them
/// together. No new UI/toggle decisions are introduced here.
extension VestigoModel {

    func scheduleBackendLibraryPush() {
        backendPushTask?.cancel()
        backendPushTask = Task { [weak self] in
            // Watching/watchlisting something is often immediately followed by backgrounding
            // the app. Without a task assertion, iOS can suspend the process mid-debounce or
            // mid-upload, silently dropping the push (same race the old CloudKit publish task
            // guarded against).
            #if canImport(UIKit)
            let bgTaskID = await MainActor.run { UIApplication.shared.beginBackgroundTask(withName: "PushFriendLibrary") }
            defer {
                Task { @MainActor in
                    guard bgTaskID != .invalid else { return }
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
            }
            #endif
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.syncSharingPrefsToBackend()
            await self.pushEnabledLibraryCategories()
            await self.pushProfileFields()
        }
    }

    func syncSharingPrefsToBackend() async {
        guard await supabaseAuth.hasSession else { return }
        let sharing = !settings.socialDontShare
        nonisolated struct Params: Encodable {
            let p_share_watchlist: Bool
            let p_share_watched: Bool
            let p_share_ratings: Bool
            let p_share_currently_watching: Bool
        }
        nonisolated struct Row: Decodable { let ok: Bool }
        do {
            let _: [Row] = try await rpc.callTable("update_sharing_prefs", params: Params(
                p_share_watchlist: sharing && settings.socialShareWatchlist,
                p_share_watched: sharing && settings.socialShareWatched,
                p_share_ratings: sharing && settings.socialShareWatched,
                p_share_currently_watching: sharing && settings.socialShareWatched
            ))
        } catch {
            logLink("syncSharingPrefsToBackend failed: \(error.localizedDescription)")
        }
    }

    func pushEnabledLibraryCategories() async {
        guard await supabaseAuth.hasSession else { return }
        let sharing = !settings.socialDontShare
        guard sharing else { return }

        if settings.socialShareWatchlist {
            await pushCategory("watchlist", payload: library.watchlistItems)
        }
        if settings.socialShareWatched {
            let watchOrderIndex = Dictionary(uniqueKeysWithValues: library.watchedOrder.enumerated().map { ($1, $0) })
            let sortedWatched = library.watchedItems.sorted {
                (watchOrderIndex[$0.key] ?? -1) > (watchOrderIndex[$1.key] ?? -1)
            }
            var datesBySid: [String: Double] = [:]
            for item in sortedWatched {
                if let d = library.watchedDates[item.key] { datesBySid[item.key.stableID] = d.timeIntervalSince1970 }
            }
            await pushCategory("watched", payload: WatchedPayload(items: sortedWatched, dates: datesBySid))

            var ratingsBySid: [String: Double] = [:]
            for item in sortedWatched + library.watchlistItems {
                if let r = library.rating(for: item.key) { ratingsBySid[item.key.stableID] = r }
            }
            await pushCategory("ratings", payload: ratingsBySid)

            await pushCategory("currently_watching", payload: library.currentlyWatchingItems)
        }
    }

    /// Featured/Excited-For and the display name are always visible to friends regardless
    /// of the sharing toggles (see migration 005's comment) — called unconditionally from
    /// scheduleBackendLibraryPush(), not gated behind `!settings.socialDontShare` the way
    /// the 4 categories above are. Also re-syncs display_name on every settings save, since
    /// it previously only synced once at sign-in and a later name change never reached the
    /// backend.
    func pushProfileFields() async {
        guard await supabaseAuth.hasSession else { return }
        let excitedForKeys = Set(settings.socialExcitedForKeys)
        let featuredItems: [MediaItem] = settings.socialFeaturedItemKeys.isEmpty
            ? Array(library.items.values.filter { library.isFavourite($0) && !excitedForKeys.contains($0.key.stableID) }.sorted { $0.voteAverage > $1.voteAverage }.prefix(SocialProfileLimits.itemLimit))
            : settings.socialFeaturedItemKeys.compactMap { k in
                guard !excitedForKeys.contains(k) else { return nil }
                return library.items.values.first { $0.key.stableID == k }
            }
        let excitedForItems: [MediaItem] = settings.socialExcitedForKeys.compactMap { k in
            library.items.values.first { $0.key.stableID == k } ?? settings.socialExcitedForItemCache.first { $0.key.stableID == k }
        }
        await supabaseAuth.updateProfileFields(featuredItems: featuredItems, excitedForItems: excitedForItems)
        await supabaseAuth.updateDisplayName(settings.name)
    }

    private func pushCategory<Payload: Encodable>(_ category: String, payload: Payload) async {
        do {
            let _: [PushCategoryRow] = try await rpc.callTable(
                "push_library_snapshot",
                params: PushCategoryParams(p_category: category, p_payload: payload)
            )
        } catch {
            logLink("pushCategory(\(category)) failed: \(error.localizedDescription)")
        }
    }
}

nonisolated struct WatchedPayload: Codable {
    let items: [MediaItem]
    let dates: [String: Double]
}

nonisolated private struct PushCategoryParams<Payload: Encodable>: Encodable {
    let p_category: String
    let p_payload: Payload
}

nonisolated private struct PushCategoryRow: Decodable {
    let revision: Int64
}
