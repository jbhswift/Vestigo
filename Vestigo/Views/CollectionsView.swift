import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WebKit)
import WebKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

// MARK: - Collections
// Franchises use a dedicated pushed screen from Collections.
// TVDB wiring should stay out of this file; use app configuration or a secure API layer for the API key.

struct CollectionsView: View {
    @ObservedObject var model: VestigoModel
    @State private var tab: CollectionsTab = .collections
    @State private var collectionPath: [UUID] = []
    @State private var showCreatePopup = false
    @State private var newCollectionName = ""
    @State private var collectionToDelete: MediaCollection?
    @State private var showDeleteAlert = false
    @State private var resetCollectionSwipe = false
    @State private var collectionToRename: MediaCollection?
    @State private var showRenameAlert = false
    @State private var renameText = ""

    private enum CollectionsTab: String, CaseIterable {
        case collections = "Collections"
        case genres = "Genres"
    }

    private var allCollectionEntries: [(collection: MediaCollection, items: [MediaItem])] {
        model.library.collections.map { collection in
            (collection, visibleItems(in: collection))
        }
    }

    private var manualCollectionEntries: [(collection: MediaCollection, items: [MediaItem])] {
        allCollectionEntries.filter { !$0.collection.isDynamic }
    }

    private var dynamicCollectionEntries: [(collection: MediaCollection, items: [MediaItem])] {
        allCollectionEntries.filter { $0.collection.isDynamic && !$0.items.isEmpty }
    }

    private var collectionIconItemsByID: [UUID: MediaItem] {
        let nonEmpty = allCollectionEntries.filter { !$0.items.isEmpty }
        return Self.collectionIconItemsByID(for: nonEmpty, library: model.library)
    }

    private func visibleItems(in collection: MediaCollection) -> [MediaItem] {
        collection.itemKeys
            .compactMap { model.library.items[$0] }
            .filter { $0.shouldShowInDiscovery }
    }

    private static func collectionIconItemsByID(for collections: [(collection: MediaCollection, items: [MediaItem])], library: UserLibrary) -> [UUID: MediaItem] {
        let sortedCollections = collections.sorted { lhs, rhs in
            if lhs.items.count != rhs.items.count {
                return lhs.items.count < rhs.items.count
            }
            return lhs.collection.name.localizedCaseInsensitiveCompare(rhs.collection.name) == .orderedAscending
        }

        var result: [UUID: MediaItem] = [:]
        var usedKeys = Set<MediaKey>()

        func sortedCandidates(for entry: (collection: MediaCollection, items: [MediaItem])) -> [MediaItem] {
            entry.items.sorted { lhs, rhs in
                lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }

        for entry in sortedCollections where entry.items.count == 1 {
            guard let item = sortedCandidates(for: entry).first else { continue }
            result[entry.collection.id] = item
            usedKeys.insert(item.key)
        }

        for entry in sortedCollections where entry.items.count > 1 {
            let candidates = sortedCandidates(for: entry)
            guard !candidates.isEmpty else { continue }

            let unusedCandidates = candidates.filter { !usedKeys.contains($0.key) }
            let usableCandidates = unusedCandidates.isEmpty ? candidates : unusedCandidates
            let iconIndex = entry.collection.name.unicodeScalars.map { Int($0.value) }.reduce(0, +) % usableCandidates.count
            let item = usableCandidates[iconIndex]

            result[entry.collection.id] = item
            usedKeys.insert(item.key)
        }

        return result
    }

    private static func collectionRowIdentity(for collection: MediaCollection, iconItem: MediaItem?) -> String {
        let itemSignature = collection.itemKeys
            .map(\.stableID)
            .sorted()
            .joined(separator: "|")
        let iconSignature = iconItem?.key.stableID ?? "folder"
        return "\(collection.id.uuidString)-\(iconSignature)-\(itemSignature)"
    }

    var body: some View {
        NavigationStack(path: $collectionPath) {
            BaseScreen(
                title: "Collections",
                filter: .constant(.both),
                settings: model.settings,
                headerAccessory: AnyView(
                    Button { showCreatePopup = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(.primary)
                            .frame(width: 42, height: 42)
                            .liquidGlass(cornerRadius: 21)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("New collection")
                ),
                onRefresh: {
                    for collection in model.library.collections {
                        await model.loadCollectionRecommendations(for: collection.id)
                    }
                }
            ) {
                VStack(spacing: 16) {
                    Picker("", selection: $tab) {
                        ForEach(CollectionsTab.allCases, id: \.self) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .liquidGlass(cornerRadius: 18)

                    if tab == .collections {
                        let favourites = model.library.orderedFavouriteItems
                        if !favourites.isEmpty {
                            FavouritesCarousel(items: favourites, model: model)
                        }

                        if manualCollectionEntries.isEmpty {
                            StatusBubble(
                                title: "No collections yet",
                                text: "Tap + to create your first collection."
                            )
                        } else {
                            ForEach(manualCollectionEntries, id: \.collection.id) { entry in
                                let collection = entry.collection
                                let iconItem = collectionIconItemsByID[collection.id]
                                Button {
                                    collectionPath.append(collection.id)
                                    AnalyticsService.shared.track(.collectionBrowsed)
                                } label: {
                                    CollectionRow(
                                        collection: collection,
                                        count: entry.items.count,
                                        iconItem: iconItem
                                    )
                                    .id(Self.collectionRowIdentity(for: collection, iconItem: iconItem))
                                }
                                .buttonStyle(.plain)
                                .swipeToDelete(cornerRadius: 22, resetTrigger: $resetCollectionSwipe) {
                                    collectionToDelete = collection
                                    showDeleteAlert = true
                                }
                                .contextMenu {
                                    Button {
                                        collectionToRename = collection
                                        renameText = collection.name
                                        showRenameAlert = true
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }
                                    Button(role: .destructive) {
                                        collectionToDelete = collection
                                        showDeleteAlert = true
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    } else {
                        NavigationLink {
                            FranchiseCollectionsView(screenMode: .series, model: model)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "film.stack")
                                    .font(.system(size: 18, weight: .bold))
                                    .frame(width: 26)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Franchises")
                                        .font(.headline.bold())
                                        .foregroundStyle(.primary)
                                    Text("Browse exact TMDb movie collections discovered from your library.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                Spacer(minLength: 0)

                                Image(systemName: "chevron.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .liquidGlass(cornerRadius: 22)
                            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        if dynamicCollectionEntries.isEmpty {
                            StatusBubble(
                                title: "No genre collections yet",
                                text: "Genre collections are generated automatically as you build your library."
                            )
                        } else {
                            ForEach(dynamicCollectionEntries, id: \.collection.id) { entry in
                                let collection = entry.collection
                                let iconItem = collectionIconItemsByID[collection.id]
                                Button {
                                    collectionPath.append(collection.id)
                                } label: {
                                    CollectionRow(
                                        collection: collection,
                                        count: entry.items.count,
                                        iconItem: iconItem
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: UUID.self) { collectionID in
                CollectionDetailView(collectionID: collectionID, model: model)
            }
        }
        .onChange(of: model.collectionsResetToken) { _, _ in
            collectionPath.removeAll()
        }
        .alert("New Collection", isPresented: $showCreatePopup) {
            TextField("Name", text: $newCollectionName)
            Button("Create") {
                model.createCollection(named: newCollectionName)
                newCollectionName = ""
            }
            Button("Cancel", role: .cancel) {
                newCollectionName = ""
            }
        }
        .alert("Delete \"\(collectionToDelete?.name ?? "")\"?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                if let c = collectionToDelete { model.deleteCollection(id: c.id) }
                collectionToDelete = nil
            }
            Button("Cancel", role: .cancel) {
                collectionToDelete = nil
                resetCollectionSwipe = true
            }
        } message: {
            Text("This cannot be undone. The collection's contents won't be affected.")
        }
        .alert("Rename Collection", isPresented: $showRenameAlert) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let c = collectionToRename { model.renameCollection(id: c.id, name: renameText) }
                collectionToRename = nil
                renameText = ""
            }
            Button("Cancel", role: .cancel) {
                collectionToRename = nil
                renameText = ""
            }
        }
    }
}

private struct FavouritesCarousel: View {
    let items: [MediaItem]
    @ObservedObject var model: VestigoModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Favourites")
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                Spacer()
                NavigationLink {
                    FavouritesCollectionView(model: model)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(items) { item in
                        Button {
                            model.selectedItem = item
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                PosterView(item: item, width: 110, height: 163, isFavourite: true)
                                Text(item.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .frame(width: 110, alignment: .leading)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
    }
}

struct FavouritesCollectionView: View {
    @ObservedObject var model: VestigoModel
    @State private var filter: MediaFilter = .both

    private var visibleItems: [MediaItem] {
        model.library.favouriteItems(for: filter)
    }

    var body: some View {
        BaseScreen(title: "Favourites", filter: $filter, settings: model.settings, onRefresh: {
            await model.loadExternalRatings(for: visibleItems, limit: 120)
        }) {
            VStack(alignment: .leading, spacing: 14) {
                FilterPills(filter: $filter, options: [.movie, .tv, .both]) { }

                if visibleItems.isEmpty {
                    StatusBubble(title: "No favourites yet", text: "Movies and series you mark as favourites will appear here.")
                } else {
                    MediaGridOrList(items: visibleItems, hideWatchedForUpcoming: false, model: model)
                }
            }
        }
    }
}
