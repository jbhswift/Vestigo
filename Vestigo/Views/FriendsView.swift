import SwiftUI
import Foundation
import PhotosUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Social Models

struct FriendProfile: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let imageData: Data?
    var recentActivity: Date?
    var featuredItems: [MediaItem] = []
    var excitedForItems: [MediaItem] = []
    var sharesWatchlist: Bool = false
    var sharesWatched: Bool = false
    var watchlistItems: [MediaItem] = []
    var watchedItems: [MediaItem] = []
    var ratings: [MediaKey: Double] = [:]
    var favouriteKeys: Set<String> = []
    var watchedDates: [String: Date] = [:]

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: FriendProfile, rhs: FriendProfile) -> Bool { lhs.id == rhs.id }
}

enum FriendsRoute: Hashable {
    case friendDetail(FriendProfile)
    case friendWatchlist(FriendProfile)
    case friendWatched(FriendProfile)
}

private enum FriendsTab { case me, friends }

// MARK: - FriendsView

struct FriendsView: View {
    @ObservedObject var model: VestigoModel
    @State private var selectedTab: FriendsTab = .me
    @State private var friendsPath: [FriendsRoute] = []
    @State private var dummyFilter: MediaFilter = .both
    @State private var loadTask: Task<Void, Never>? = nil
    @State private var showAddMenu = false
    @State private var showQRCode = false
    @State private var showSendLink = false
    @State private var isPreparingInvite = false
    @AppStorage("Vestigo.devMode") private var devMode: Bool = false

    private var myInviteURL: String { model.myInviteURL }

    var body: some View {
        ZStack {
            NavigationStack(path: $friendsPath) {
                BaseScreen(title: "Friends", filter: $dummyFilter, settings: model.settings, headerAccessory: AnyView(
                    Button { showAddMenu = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 42, height: 42)
                            .liquidGlass(cornerRadius: 21)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Add friends")
                ), onRefresh: { startFriendsLoad() }) {
                    VStack(spacing: 22) {
                        Picker("", selection: $selectedTab) {
                            Text("Me").tag(FriendsTab.me)
                            Text("Friends").tag(FriendsTab.friends)
                        }
                        .pickerStyle(.segmented)
                        .liquidGlass(cornerRadius: 18)

                        if selectedTab == .me {
                            MeSectionView(model: model)
                        } else {
                            FriendsListView(
                                friends: model.friends,
                                model: model,
                                isLoading: model.friendsLoading,
                                diagnostic: model.friendsDiagnostic,
                                onSelect: { friend in
                                    friendsPath.append(.friendDetail(friend))
                                    AnalyticsService.shared.track(.friendProfileViewed)
                                }
                            )
                        }

                        if devMode && !model.linkLog.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Link Log")
                                        .font(.caption.bold())
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Clear") { model.linkLog.removeAll() }
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                ForEach(model.linkLog, id: \.self) { entry in
                                    Text(entry)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .padding(12)
                            .liquidGlass(cornerRadius: 20)
                        }
                    }
                }
                .navigationDestination(for: FriendsRoute.self) { route in
                    switch route {
                    case .friendDetail(let friend):
                        FriendDetailPage(friend: friend, model: model, onWatchlist: {
                            friendsPath.append(.friendWatchlist(friend))
                        }, onWatched: {
                            friendsPath.append(.friendWatched(friend))
                        })
                    case .friendWatchlist(let friend):
                        FriendWatchlistPage(friend: friend, model: model)
                    case .friendWatched(let friend):
                        FriendWatchedPage(friend: friend, model: model)
                    }
                }
                .onChange(of: model.friendsResetToken) { _, _ in
                    friendsPath.removeAll()
                    selectedTab = .me
                }
                .onChange(of: model.pendingFriendAdd) { _, newValue in
                    if newValue != nil { selectedTab = .friends }
                }
                .onAppear {
                    // Handle the case where pendingFriendAdd was set before this view appeared
                    if model.pendingFriendAdd != nil { selectedTab = .friends }
                }
            }

            if showQRCode {
                QRCodeOverlay(inviteURL: myInviteURL, onDismiss: { showQRCode = false })
                    .transition(.opacity.animation(.easeInOut(duration: 0.2)))
            }

            if isPreparingInvite {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .transition(.opacity)
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.6)
                    .transition(.opacity)
            }
        }
        .task { await startFriendsLoadAsync() }
        .alert("Add a Friend", isPresented: $showAddMenu) {
            Button("QR Code") {
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000) // let alert finish dismissing
                    withAnimation(.easeInOut(duration: 0.22)) { isPreparingInvite = true }
                    await model.publishPublicProfile()
                    withAnimation(.easeInOut(duration: 0.22)) { isPreparingInvite = false }
                    showQRCode = true
                }
            }
            Button("Send Link") {
                Task {
                    try? await Task.sleep(nanoseconds: 300_000_000)
                    withAnimation(.easeInOut(duration: 0.22)) { isPreparingInvite = true }
                    await model.publishPublicProfile()
                    withAnimation(.easeInOut(duration: 0.22)) { isPreparingInvite = false }
                    showSendLink = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Share your Vestigo profile so friends can add you.")
        }
        .sheet(isPresented: $showSendLink) {
            #if canImport(UIKit)
            let shareItems: [Any] = URL(string: myInviteURL).map { [$0 as Any] } ?? [myInviteURL as Any]
            ActivityView(activityItems: shareItems)
            #else
            EmptyView()
            #endif
        }
        .alert(
            "Friend Removed",
            isPresented: Binding(
                get: { !model.pendingRemovalNames.isEmpty },
                set: { if !$0 { model.pendingRemovalNames.removeAll() } }
            )
        ) {
            Button("OK") { model.pendingRemovalNames.removeAll() }
        } message: {
            if let name = model.pendingRemovalNames.first {
                let others = model.pendingRemovalNames.count - 1
                if others == 0 {
                    Text("\(name) has removed you as a friend on Vestigo.")
                } else {
                    Text("\(name) and \(others) other\(others == 1 ? "" : "s") have removed you as friends on Vestigo.")
                }
            }
        }
    }

    private func startFriendsLoad() {
        loadTask?.cancel()
        loadTask = Task { await startFriendsLoadAsync() }
    }

    private func startFriendsLoadAsync() async {
        async let publish: Void = model.publishPublicProfile()
        async let requests: Void = model.checkIncomingFriendRequests()
        _ = await (publish, requests)
        await model.loadFriends()
    }
}

// MARK: - QR Code Overlay

private struct QRCodeOverlay: View {
    let inviteURL: String
    let onDismiss: () -> Void

    @State private var savedBrightness: CGFloat = 0.5
    @State private var qrImage: UIImage? = nil

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 20) {
                Text("Scan to add me on Vestigo")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)

                if let image = qrImage {
                    Image(uiImage: image)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 260, height: 260)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.secondary.opacity(0.2))
                        .frame(width: 260, height: 260)
                        .overlay(ProgressView())
                }

                Text("Tap anywhere to close")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .liquidGlass(cornerRadius: 32)
            .padding(24)
        }
        .onAppear {
            #if canImport(UIKit)
            savedBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1.0
            #endif
            generateQR()
        }
        .onDisappear {
            #if canImport(UIKit)
            UIScreen.main.brightness = savedBrightness
            #endif
        }
    }

    private func generateQR() {
        #if canImport(UIKit)
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = inviteURL.data(using: .utf8) else { return }
            let filter = CIFilter(name: "CIQRCodeGenerator")
            filter?.setValue(data, forKey: "inputMessage")
            filter?.setValue("M", forKey: "inputCorrectionLevel")
            guard let output = filter?.outputImage else { return }
            let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
            let context = CIContext()
            guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return }
            let image = UIImage(cgImage: cgImage)
            DispatchQueue.main.async { qrImage = image }
        }
        #endif
    }
}
