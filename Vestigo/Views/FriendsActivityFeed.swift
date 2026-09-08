import SwiftUI
import Foundation

// MARK: - Friend Activity Row

struct FriendActivityRow: View {
    let friend: FriendProfile
    let item: MediaItem
    @ObservedObject var model: VestigoModel

    var body: some View {
        Button { model.selectedItem = item } label: {
            HStack(spacing: 12) {
                AvatarView(name: friend.name, imageData: friend.imageData, size: 54)
                VStack(alignment: .leading, spacing: 2) {
                    let first = friend.name.components(separatedBy: " ").first ?? friend.name
                    Text("\(first) watched")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(item.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let date = friend.watchedDates[item.key.stableID] {
                        Text(date.formatted(.relative(presentation: .named)))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                PosterView(item: item, width: 42, height: 62, isFavourite: false)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .liquidGlass(cornerRadius: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Friend Favourites Carousel

struct FriendFavouritesSection: View {
    let friends: [FriendProfile]
    @ObservedObject var model: VestigoModel

    private struct ScoredItem: Identifiable {
        var id: String { item.key.stableID }
        let item: MediaItem
        let overlap: Int
        let friendNames: [String]
        let firstFriend: FriendProfile?
    }

    private var scoredItems: [ScoredItem] {
        var counts: [String: Int] = [:]
        var itemMap: [String: MediaItem] = [:]
        var nameMap: [String: [String]] = [:]
        var firstFriendMap: [String: FriendProfile] = [:]
        for friend in friends {
            let first = friend.name.components(separatedBy: " ").first ?? friend.name
            let favKeys = friend.favouriteKeys
            var friendFavItems: [MediaItem]
            if favKeys.isEmpty {
                friendFavItems = friend.featuredItems
            } else {
                friendFavItems = friend.featuredItems.filter { favKeys.contains($0.key.stableID) }
                if friend.sharesWatched {
                    let existingIDs = Set(friendFavItems.map { $0.key.stableID })
                    let watchedFavs = friend.watchedItems.filter {
                        favKeys.contains($0.key.stableID) && !existingIDs.contains($0.key.stableID)
                    }
                    friendFavItems += watchedFavs
                }
            }
            for item in friendFavItems {
                let sid = item.key.stableID
                counts[sid, default: 0] += 1
                itemMap[sid] = item
                if firstFriendMap[sid] == nil { firstFriendMap[sid] = friend }
                if let rating = friend.ratings[item.key], rating > 0 {
                    let r = rating.formatted(.number.precision(.fractionLength(0...1)))
                    nameMap[sid, default: []].append("\(first) · \(r)")
                } else {
                    nameMap[sid, default: []].append(first)
                }
            }
        }
        return Array(itemMap.values)
            .sorted { a, b in
                let ao = counts[a.key.stableID] ?? 1, bo = counts[b.key.stableID] ?? 1
                if ao != bo { return ao > bo }
                let au = !model.library.isWatched(a.key), bu = !model.library.isWatched(b.key)
                if au != bu { return au }
                return a.voteAverage > b.voteAverage
            }
            .map { item in
                let sid = item.key.stableID
                return ScoredItem(item: item, overlap: counts[sid] ?? 1, friendNames: nameMap[sid] ?? [], firstFriend: firstFriendMap[sid])
            }
    }

    var body: some View {
        if !scoredItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Friend Favourites")
                    .font(.headline.bold())
                    .padding(.horizontal, 2)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(scoredItems.prefix(15))) { scored in
                            Button {
                                model.friendDetailContext = scored.firstFriend
                                model.selectedItem = scored.item
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    PosterView(
                                        item: scored.item,
                                        width: 100,
                                        height: 150,
                                        isFavourite: true,
                                        favouriteColor: model.library.isFavourite(scored.item) ? .yellow : .blue
                                    )
                                    Text(scored.item.title)
                                        .font(.caption.bold())
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .frame(width: 100, alignment: .leading)
                                    Text(scored.friendNames.prefix(2).joined(separator: ", "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .frame(width: 100, alignment: .leading)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
                .scrollClipDisabled()
            }
        }
    }
}

// MARK: - Watch With Carousel

private struct FriendPickerMenu: View {
    @Binding var selectionID: String?
    let availableFriends: [FriendProfile]
    var excluded: [String] = []
    let placeholder: String

    private var eligibleFriends: [FriendProfile] {
        availableFriends.filter { !excluded.contains($0.id) }
    }

    private var selectedFriend: FriendProfile? {
        selectionID.flatMap { id in availableFriends.first { $0.id == id } }
    }

    var body: some View {
        Menu {
            Button { selectionID = nil } label: {
                Label("Anyone", systemImage: "person.2")
            }
            ForEach(eligibleFriends) { friend in
                Button { selectionID = friend.id } label: {
                    let firstName = friend.name.components(separatedBy: " ").first ?? friend.name
                    Label(firstName, systemImage: "person")
                }
            }
        } label: {
            HStack(spacing: 3) {
                if let friend = selectedFriend {
                    Text(friend.name.components(separatedBy: " ").first ?? friend.name)
                        .font(.headline.bold())
                        .foregroundStyle(.primary)
                } else {
                    Text(placeholder)
                        .font(.headline.bold())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .liquidGlass(cornerRadius: 10)
        }
    }
}

struct WatchWithSection: View {
    let friends: [FriendProfile]
    @ObservedObject var model: VestigoModel

    @State private var selectedFriendID1: String? = nil
    @State private var selectedFriendID2: String? = nil

    private var sharingFriends: [FriendProfile] {
        friends.filter { $0.sharesWatchlist }
    }

    private var selectedFriend1: FriendProfile? {
        selectedFriendID1.flatMap { id in sharingFriends.first { $0.id == id } }
    }

    private var selectedFriend2: FriendProfile? {
        selectedFriendID2.flatMap { id in sharingFriends.first { $0.id == id } }
    }

    private struct ScoredItem: Identifiable {
        var id: String { item.key.stableID }
        let item: MediaItem
        let labels: [String]
        let overlapCount: Int
    }

    private var scoredItems: [ScoredItem] {
        let myWatchlistItems = model.library.watchlistItems
        let myIDs = Set(myWatchlistItems.map { $0.key.stableID })
        var myItemsByID: [String: MediaItem] = [:]
        for item in myWatchlistItems { myItemsByID[item.key.stableID] = item }

        if let f1 = selectedFriend1, let f2 = selectedFriend2 {
            // Two friends: show items shared by any 2-of-3 combination (you, f1, f2)
            let f1IDs = Set(f1.watchlistItems.map { $0.key.stableID })
            let f2IDs = Set(f2.watchlistItems.map { $0.key.stableID })
            let f1Name = f1.name.components(separatedBy: " ").first ?? f1.name
            let f2Name = f2.name.components(separatedBy: " ").first ?? f2.name

            return myIDs.union(f1IDs).union(f2IDs).compactMap { sid -> ScoredItem? in
                let inMe = myIDs.contains(sid)
                let inF1 = f1IDs.contains(sid)
                let inF2 = f2IDs.contains(sid)
                let count = (inMe ? 1 : 0) + (inF1 ? 1 : 0) + (inF2 ? 1 : 0)
                guard count >= 2 else { return nil }
                let item = myItemsByID[sid]
                    ?? f1.watchlistItems.first { $0.key.stableID == sid }
                    ?? f2.watchlistItems.first { $0.key.stableID == sid }
                guard let item else { return nil }
                var who: [String] = []
                if inF1 { who.append(f1Name) }
                if inF2 { who.append(f2Name) }
                return ScoredItem(item: item, labels: who, overlapCount: count)
            }.sorted { a, b in
                a.overlapCount != b.overlapCount ? a.overlapCount > b.overlapCount : a.item.voteAverage > b.item.voteAverage
            }
        } else if let f1 = selectedFriend1 {
            // One friend: intersection of your watchlist and their watchlist
            let f1IDs = Set(f1.watchlistItems.map { $0.key.stableID })
            let f1Name = f1.name.components(separatedBy: " ").first ?? f1.name
            return myIDs.intersection(f1IDs).compactMap { sid -> ScoredItem? in
                guard let item = myItemsByID[sid] else { return nil }
                return ScoredItem(item: item, labels: [f1Name], overlapCount: 2)
            }.sorted { $0.item.voteAverage > $1.item.voteAverage }
        } else {
            // No friend selected: items on your watchlist that any sharing friend also has
            var counts: [String: Int] = [:]
            var nameMap: [String: [String]] = [:]
            for friend in sharingFriends {
                let firstName = friend.name.components(separatedBy: " ").first ?? friend.name
                let fIDs = Set(friend.watchlistItems.map { $0.key.stableID })
                for sid in myIDs.intersection(fIDs) {
                    counts[sid, default: 0] += 1
                    nameMap[sid, default: []].append(firstName)
                }
            }
            return counts.compactMap { sid, count -> ScoredItem? in
                guard let item = myItemsByID[sid] else { return nil }
                return ScoredItem(item: item, labels: nameMap[sid] ?? [], overlapCount: count)
            }.sorted { a, b in
                a.overlapCount != b.overlapCount ? a.overlapCount > b.overlapCount : a.item.voteAverage > b.item.voteAverage
            }
        }
    }

    var body: some View {
        if !sharingFriends.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    Text("Watch with")
                        .font(.headline.bold())

                    FriendPickerMenu(
                        selectionID: $selectedFriendID1,
                        availableFriends: sharingFriends,
                        excluded: [selectedFriendID2].compactMap { $0 },
                        placeholder: "anyone"
                    )

                    if selectedFriendID1 != nil {
                        Text("&")
                            .font(.headline.bold())
                        FriendPickerMenu(
                            selectionID: $selectedFriendID2,
                            availableFriends: sharingFriends,
                            excluded: [selectedFriendID1].compactMap { $0 },
                            placeholder: "anyone"
                        )
                    }

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 2)

                if scoredItems.isEmpty {
                    Text(selectedFriendID1 != nil
                        ? "Nothing shared on your watchlists yet."
                        : "No watchlist overlap with your friends yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 2)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(Array(scoredItems.prefix(20))) { scored in
                                Button { model.selectedItem = scored.item } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        PosterView(
                                            item: scored.item,
                                            width: 100,
                                            height: 150,
                                            isFavourite: model.library.isFavourite(scored.item)
                                        )
                                        Text(scored.item.title)
                                            .font(.caption.bold())
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                            .frame(width: 100, alignment: .leading)
                                        Text(scored.labels.prefix(2).joined(separator: ", "))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .frame(width: 100, alignment: .leading)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .scrollClipDisabled()
                }
            }
            .onChange(of: selectedFriendID1) { _, newValue in
                if newValue == nil { selectedFriendID2 = nil }
            }
        }
    }
}
