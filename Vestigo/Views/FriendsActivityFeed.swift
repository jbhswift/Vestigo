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
                    let watchDate = friend.watchedDates[item.key.stableID] ?? friend.recentActivity
                    if let date = watchDate {
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

// MARK: - Friend Excited For Carousel

struct FriendExcitedForSection: View {
    let friends: [FriendProfile]
    @ObservedObject var model: VestigoModel

    private struct ScoredItem: Identifiable {
        var id: String { item.key.stableID }
        let item: MediaItem
        let overlap: Int
        let friendLabels: [String]
    }

    private var scoredItems: [ScoredItem] {
        var counts: [String: Int] = [:]
        var itemMap: [String: MediaItem] = [:]
        var labelMap: [String: [String]] = [:]
        for friend in friends {
            let first = friend.name.components(separatedBy: " ").first ?? friend.name
            for item in friend.excitedForItems {
                let sid = item.key.stableID
                counts[sid, default: 0] += 1
                itemMap[sid] = item
                if let date = item.releaseDateValue {
                    let dateStr = date.formatted(.dateTime.day().month(.defaultDigits).year(.twoDigits))
                    labelMap[sid, default: []].append("\(first) · \(dateStr)")
                } else {
                    labelMap[sid, default: []].append(first)
                }
            }
        }
        return Array(itemMap.values)
            .sorted { a, b in
                let ao = counts[a.key.stableID] ?? 1, bo = counts[b.key.stableID] ?? 1
                if ao != bo { return ao > bo }
                let ad = a.releaseDateValue ?? .distantFuture
                let bd = b.releaseDateValue ?? .distantFuture
                return ad < bd
            }
            .map { item in
                let sid = item.key.stableID
                return ScoredItem(item: item, overlap: counts[sid] ?? 1, friendLabels: labelMap[sid] ?? [])
            }
    }

    var body: some View {
        if !scoredItems.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Friends are excited for")
                    .font(.headline.bold())
                    .padding(.horizontal, 2)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(Array(scoredItems.prefix(15))) { scored in
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
                                    Text(scored.friendLabels.prefix(2).joined(separator: ", "))
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
