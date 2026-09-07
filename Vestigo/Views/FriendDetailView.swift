import SwiftUI
import Foundation

// MARK: - Friend Detail Page

struct FriendDetailPage: View {
    let friend: FriendProfile
    @ObservedObject var model: VestigoModel
    let onWatchlist: () -> Void
    let onWatched: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var dummyFilter: MediaFilter = .both
    @State private var showRemoveConfirm = false
    @State private var liveData: FriendProfile? = nil

    private var current: FriendProfile { liveData ?? friend }

    private func refresh() {
        Task {
            if let updated = await model.refreshFriend(recordID: friend.id) { liveData = updated }
        }
    }

    var body: some View {
        BaseScreen(title: "", filter: $dummyFilter, settings: model.settings, onRefresh: { refresh() }) {
            VStack(spacing: 22) {
                VStack(spacing: 12) {
                    AvatarView(name: current.name, imageData: current.imageData, size: 110)
                    VStack(spacing: 4) {
                        Text(current.name)
                            .font(.title.bold())
                            .minimumScaleFactor(0.6)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                        if let activity = current.recentActivity {
                            Text("Active \(activity.formatted(.relative(presentation: .named)))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)

                if !current.featuredItems.isEmpty {
                    SocialPosterRow(title: "Featured", items: current.featuredItems, showRating: false, friendContext: current, model: model)
                }

                if !current.excitedForItems.isEmpty {
                    SocialPosterRow(title: "Excited For", items: current.excitedForItems, showRating: false, friendContext: current, model: model)
                }

                VStack(spacing: 0) {
                    if current.sharesWatchlist {
                        Button { onWatchlist() } label: {
                            HStack {
                                Label("View Watchlist (\(current.watchlistItems.count))", systemImage: "bookmark")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if current.sharesWatchlist && current.sharesWatched {
                        Divider().padding(.leading, 16)
                    }

                    if current.sharesWatched {
                        Button { onWatched() } label: {
                            HStack {
                                Label("View Watched (\(current.watchedItems.count))", systemImage: "checkmark.circle")
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if !current.sharesWatchlist && !current.sharesWatched {
                        HStack(spacing: 8) {
                            Image(systemName: "eye.slash")
                                .foregroundStyle(.secondary)
                            Text("\(current.name) isn't sharing their library.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                    }
                }
                .liquidGlass(cornerRadius: 20)

                Button(role: .destructive) {
                    showRemoveConfirm = true
                } label: {
                    Label("Remove Friend", systemImage: "person.badge.minus")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .liquidGlass(cornerRadius: 20)
                }
                .buttonStyle(.plain)
                .alert("Remove \(current.name)?", isPresented: $showRemoveConfirm) {
                    Button("Remove", role: .destructive) {
                        model.removeFriend(recordID: friend.id)
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("You'll no longer see their profile. They won't be notified.")
                }
            }
        }
    }
}

// MARK: - Friend Watchlist Page

struct FriendWatchlistPage: View {
    let friend: FriendProfile
    @ObservedObject var model: VestigoModel
    @State private var filter: MediaFilter = .both
    @State private var liveData: FriendProfile? = nil

    private var current: FriendProfile { liveData ?? friend }

    private func refresh() {
        Task {
            if let updated = await model.refreshFriend(recordID: friend.id) { liveData = updated }
        }
    }

    private var filteredItems: [MediaItem] {
        switch filter {
        case .movie: return current.watchlistItems.filter { $0.kind == .movie }
        case .tv: return current.watchlistItems.filter { $0.kind == .tv }
        case .both: return current.watchlistItems
        }
    }

    var body: some View {
        BaseScreen(title: "\(current.name)'s Watchlist", filter: $filter, settings: model.settings, onRefresh: { refresh() }) {
            VStack(spacing: 16) {
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
                if filteredItems.isEmpty {
                    StatusBubble(title: "Nothing here", text: "\(current.name)'s watchlist is empty.")
                } else {
                    MediaGridOrList(items: filteredItems, hideWatchedForUpcoming: false, model: model, openItem: { item in
                        model.friendDetailContext = current
                        model.selectedItem = item
                    })
                }
            }
        }
    }
}

// MARK: - Friend Watched Page

struct FriendWatchedPage: View {
    let friend: FriendProfile
    @ObservedObject var model: VestigoModel
    @State private var filter: MediaFilter = .both
    @State private var hideAlreadySeen = false
    @State private var liveData: FriendProfile? = nil

    private var current: FriendProfile { liveData ?? friend }

    private func refresh() {
        Task {
            if let updated = await model.refreshFriend(recordID: friend.id) { liveData = updated }
        }
    }

    private var filteredItems: [MediaItem] {
        var items = current.watchedItems
        switch filter {
        case .movie: items = items.filter { $0.kind == .movie }
        case .tv: items = items.filter { $0.kind == .tv }
        case .both: break
        }
        if hideAlreadySeen { items = items.filter { !model.library.isWatched($0.key) } }
        return items
    }

    var body: some View {
        BaseScreen(title: "\(current.name)'s Watched", filter: $filter, settings: model.settings, onRefresh: { refresh() }) {
            VStack(spacing: 16) {
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
                Toggle("Hide items I've seen", isOn: $hideAlreadySeen)
                    .font(.subheadline)
                    .padding(.horizontal, 4)
                if filteredItems.isEmpty {
                    StatusBubble(title: "Nothing here", text: "\(current.name) hasn't watched anything yet.")
                } else {
                    MediaGridOrList(items: filteredItems, hideWatchedForUpcoming: false, model: model, openItem: { item in
                        model.friendDetailContext = current
                        model.selectedItem = item
                    })
                }
            }
        }
    }
}
