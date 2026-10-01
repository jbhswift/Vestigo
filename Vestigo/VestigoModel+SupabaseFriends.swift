import Foundation

/// Backend-mediated friends system — invites, friend list, and removal. Replaces the old
/// CloudKit-based VestigoModel+Friends.swift entirely as of Stage 6.
extension VestigoModel {

    /// get_my_friends() returns identity fields (name/avatar/featured/excited-for) for every
    /// confirmed friend; get_friend_library(friend_id) is then called per friend for their
    /// gated watchlist/watched/ratings/currently-watching payload, alongside the real
    /// sharing_prefs booleans (migration 007) — needed because an *enabled-but-never-pushed*
    /// category and a *disabled* category would otherwise look identical (both absent from
    /// the JSON payload), and FriendDetailView renders those two states differently.
    func loadFriends() async {
        friendsLoading = true
        guard await supabaseAuth.hasSession else {
            friends = []
            friendsLoading = false
            return
        }

        do {
            let friendRows: [SupabaseFriendRow] = try await rpc.callTable("get_my_friends")
            var profiles: [FriendProfile] = []
            for row in friendRows {
                if let profile = try await buildFriendProfile(from: row) {
                    profiles.append(profile)
                }
            }
            friends = profiles
            friendsDiagnostic = ""
            if !profiles.isEmpty { saveFriendsCache() }
        } catch {
            logLink("loadFriends failed: \(error.localizedDescription)")
            friendsDiagnostic = error.localizedDescription
        }
        friendsLoading = false
    }

    /// Refreshes a single friend in-place (e.g. when their detail page is opened), rather
    /// than reloading everyone via loadFriends().
    func refreshFriend(friendID: String) async -> FriendProfile? {
        do {
            let friendRows: [SupabaseFriendRow] = try await rpc.callTable("get_my_friends")
            guard let row = friendRows.first(where: { $0.friend_id == friendID }) else { return nil }
            guard let profile = try await buildFriendProfile(from: row) else { return nil }
            if let idx = friends.firstIndex(where: { $0.id == friendID }) {
                friends[idx] = profile
            }
            return profile
        } catch {
            logLink("refreshFriend failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func buildFriendProfile(from row: SupabaseFriendRow) async throws -> FriendProfile? {
        nonisolated struct LibraryParams: Encodable { let p_friend_id: String }
        let libraryRows: [SupabaseFriendLibraryRow] = try await rpc.callTable(
            "get_friend_library",
            params: LibraryParams(p_friend_id: row.friend_id)
        )
        guard let libraryRow = libraryRows.first else { return nil }
        let payload = libraryRow.payload

        let watchlistItems = payload.watchlist ?? []
        let watchedItems = payload.watched?.items ?? []
        let watchedDates = Dictionary(
            uniqueKeysWithValues: (payload.watched?.dates ?? [:]).map { ($0.key, Date(timeIntervalSince1970: $0.value)) }
        )
        let ratingsBySid = payload.ratings ?? [:]
        var ratings: [MediaKey: Double] = [:]
        for item in watchedItems + watchlistItems {
            if let r = ratingsBySid[item.key.stableID] { ratings[item.key] = r }
        }

        return FriendProfile(
            id: row.friend_id,
            name: (row.display_name?.isEmpty == false) ? row.display_name! : "Vestigo user",
            imageData: nil,
            recentActivity: watchedDates.values.max(),
            featuredItems: row.featured_items,
            excitedForItems: row.excited_for_items,
            sharesWatchlist: libraryRow.share_watchlist,
            sharesWatched: libraryRow.share_watched,
            watchlistItems: watchlistItems,
            watchedItems: watchedItems,
            ratings: ratings,
            favouriteKeys: [],
            watchedDates: watchedDates,
            currentlyWatchingItems: payload.currently_watching ?? []
        )
    }

    /// Creates a new single-use invite via the backend and returns its shareable URL.
    /// Returns nil (and records the failure in `friendsDiagnostic`, the same field the
    /// old CloudKit path already used for user-visible diagnostics) on failure — e.g. not
    /// signed in yet, or rate-limited.
    func createInviteURL() async -> String? {
        nonisolated struct Row: Decodable { let token: String }
        do {
            let rows: [Row] = try await rpc.callTable("create_invite")
            guard let row = rows.first else { return nil }
            return "https://vestigo-app.com/friend?t=\(row.token)"
        } catch {
            logLink("createInviteURL failed: \(error.localizedDescription)")
            friendsDiagnostic = error.localizedDescription
            return nil
        }
    }

    /// Called when a friend invite link is opened. Looks up the token's real, server-stored
    /// inviter name — never a URL parameter — and shows the Add Friend confirmation if the
    /// token is still valid.
    func handleFriendInviteLink(token: String) async {
        nonisolated struct Params: Encodable { let p_token: String }
        nonisolated struct Row: Decodable { let display_name: String?; let avatar_url: String?; let valid: Bool }
        do {
            let rows: [Row] = try await rpc.callTable("get_invite_preview", params: Params(p_token: token))
            guard let row = rows.first, row.valid else {
                logLink("handleFriendInviteLink: token invalid or expired")
                return
            }
            let name = (row.display_name?.isEmpty == false) ? row.display_name! : "this person"
            await MainActor.run {
                pendingFriendAdd = PendingFriendAdd(id: token, name: name)
                selectTab(.friends)
            }
        } catch {
            logLink("handleFriendInviteLink failed: \(error.localizedDescription)")
        }
    }

    /// Called from the Add Friend confirmation. Atomically consumes the single-use invite
    /// token server-side and creates the mutual friendship in one step — no second
    /// approval from the inviter, matching the existing product flow.
    func acceptFriendInvite(token: String) {
        pendingFriendAdd = nil
        Task {
            nonisolated struct Params: Encodable { let p_token: String }
            nonisolated struct Row: Decodable { let friend_user_id: String }
            do {
                let rows: [Row] = try await rpc.callTable("accept_invite", params: Params(p_token: token))
                if rows.first != nil {
                    AnalyticsService.shared.track(.friendAdded)
                    await loadFriends()
                }
            } catch {
                logLink("acceptFriendInvite failed: \(error.localizedDescription)")
                friendsDiagnostic = error.localizedDescription
            }
        }
    }

    /// Bidirectional removal is enforced server-side by remove_friend() deleting the single
    /// shared friendships row (see migration 002/009), so there's no separate "removal
    /// notice" to send; the other side's next get_my_friends()/get_friend_library() call
    /// simply stops returning this friend/their data, immediately.
    func removeFriend(friendID: String) {
        friends.removeAll { $0.id == friendID }
        clearFriendsCache()
        Task {
            nonisolated struct Params: Encodable { let p_friend_id: String }
            nonisolated struct Row: Decodable { let ok: Bool }
            do {
                let _: [Row] = try await rpc.callTable("remove_friend", params: Params(p_friend_id: friendID))
            } catch {
                logLink("removeFriend failed: \(error.localizedDescription)")
                friendsDiagnostic = error.localizedDescription
            }
            await loadFriends()
        }
    }
}

nonisolated private struct SupabaseFriendRow: Decodable {
    let friend_id: String
    let display_name: String?
    let avatar_url: String?
    let featured_items: [MediaItem]
    let excited_for_items: [MediaItem]
}

nonisolated private struct SupabaseWatchedBucket: Decodable {
    let items: [MediaItem]
    let dates: [String: Double]
}

nonisolated private struct SupabaseLibraryPayload: Decodable {
    let watchlist: [MediaItem]?
    let watched: SupabaseWatchedBucket?
    let ratings: [String: Double]?
    let currently_watching: [MediaItem]?
}

nonisolated private struct SupabaseFriendLibraryRow: Decodable {
    let payload: SupabaseLibraryPayload
    let share_watchlist: Bool
    let share_watched: Bool
}
