import SwiftUI
import Foundation

// MARK: - Friends List

struct FriendsListView: View {
    let friends: [FriendProfile]
    @ObservedObject var model: VestigoModel
    var isLoading: Bool = false
    var diagnostic: String = ""
    let onSelect: (FriendProfile) -> Void
    @AppStorage("Vestigo.devMode") private var devMode: Bool = false
    @State private var friendToRemove: FriendProfile? = nil

    var body: some View {
        VStack(spacing: 16) {
            if isLoading && friends.isEmpty {
                StatusBubble(
                    title: "Loading friends…",
                    text: "Fetching profiles for your added friends."
                )
            } else if friends.isEmpty {
                StatusBubble(
                    title: "No friends added yet",
                    text: "Tap the + button to share your QR code or send a link so friends can add you."
                )
                if devMode && !diagnostic.isEmpty {
                    Text(diagnostic)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 4)
                }
            } else {
                FriendFavouritesSection(friends: friends, model: model)
                FriendExcitedForSection(friends: friends, model: model)

                ForEach(friends) { friend in
                    Button { onSelect(friend) } label: {
                        HStack(spacing: 14) {
                            AvatarView(name: friend.name, imageData: friend.imageData, size: 54)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(friend.name)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                if let activity = friend.recentActivity {
                                    Text("Active \(activity.formatted(.relative(presentation: .named)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let lastItem = friend.watchedItems.first {
                                    HStack(spacing: 4) {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.tertiary)
                                        Text(lastItem.title)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .liquidGlass(cornerRadius: 30)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button(role: .destructive) {
                            friendToRemove = friend
                        } label: {
                            Label("Remove Friend", systemImage: "person.badge.minus")
                        }
                    }
                }
            }
        }
        .alert("Remove \(friendToRemove?.name ?? "")?", isPresented: Binding(
            get: { friendToRemove != nil },
            set: { if !$0 { friendToRemove = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let f = friendToRemove { model.removeFriend(recordID: f.id) }
                friendToRemove = nil
            }
            Button("Cancel", role: .cancel) { friendToRemove = nil }
        } message: {
            Text("They will be removed from your friends list.")
        }
    }
}
