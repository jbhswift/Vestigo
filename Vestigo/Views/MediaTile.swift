import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - MediaTile

struct MediaTile: View {
    let item: MediaItem
    let hideWatched: Bool
    @ObservedObject var model: VestigoModel
    var openItem: ((MediaItem) -> Void)? = nil
    var swipeContext: SwipeContext = .none
    @State private var showCollections = false

    var body: some View {
        tileCore
    }

    private var tileCore: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { openTileItem() } label: {
                PosterView(item: item, width: 148, height: 214, isFavourite: model.library.isFavourite(item))
            }
            .buttonStyle(.plain)

            .contextMenu {
                MediaItemContextMenuActions(item: item, hideWatched: hideWatched, model: model, swipeContext: swipeContext) {
                    showCollections = true
                }
            }
            .sheet(isPresented: $showCollections) {
                AddToCollectionSheet(item: item, model: model)
            }

            Text(item.title)
                .font(.subheadline.bold())
                .lineLimit(2)
                .frame(width: 148, alignment: .topLeading)
                .frame(minHeight: 36, alignment: .topLeading)

            Text(tileMetadataText)
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .frame(width: 148, alignment: .leading)

            HStack(spacing: 7) {
                TileIconButton(
                    systemName: model.library.isInWatchlist(item.key) ? "bookmark.fill" : "bookmark",
                    tint: .white
                ) {
                    model.toggleWatchlist(item)
                }

                if !hideWatched && !item.isUpcoming {
                    TileIconButton(
                        systemName: model.library.isWatched(item.key) ? "checkmark.circle.fill" : "checkmark.circle",
                        tint: .white
                    ) {
                        model.toggleWatched(item)
                    }
                }
            }
            .frame(width: 148, alignment: .leading)
            .frame(minHeight: 30, alignment: .leading)
        }
        .frame(width: 148, alignment: .topLeading)
        .task(id: item.key) {
            await model.loadExternalRatings(item)
        }
    }

    private func openTileItem() {
        if let openItem {
            openItem(item)
        } else {
            model.selectedItem = item
        }
    }

    private var tileMetadataText: String {
        let ratingText = model.ratingDisplayText(for: item)
        if ratingText.isEmpty {
            return item.releaseDateReadable
        }
        return "\(item.releaseDateReadable) • \(ratingText)"
    }
}

// MARK: - MediaItemContextMenuActions

struct MediaItemContextMenuActions: View {
    let item: MediaItem
    let hideWatched: Bool
    @ObservedObject var model: VestigoModel
    var swipeContext: SwipeContext = .none
    let showCollections: () -> Void

    var body: some View {
        Button {
            showCollections()
        } label: {
            Label("Add to collection", systemImage: "folder.badge.plus")
        }

        Button {
            model.toggleWatchlist(item)
        } label: {
            Label(
                model.library.isInWatchlist(item.key) ? "Remove saved" : "Save",
                systemImage: model.library.isInWatchlist(item.key) ? "bookmark.slash" : "bookmark"
            )
        }

        if !hideWatched && !item.isUpcoming {
            Button {
                model.toggleWatched(item)
            } label: {
                Label(
                    model.library.isWatched(item.key) ? "Mark unwatched" : "Mark watched",
                    systemImage: model.library.isWatched(item.key) ? "checkmark.circle.fill" : "checkmark.circle"
                )
            }
        }

        if model.library.isWatched(item.key) {
            Button {
                model.requestToggleFavourite(item)
            } label: {
                Label(
                    model.library.isFavourite(item) ? "Remove favourite" : "Mark favourite",
                    systemImage: model.library.isFavourite(item) ? "star.slash" : "star"
                )
            }
        }

        Button {
            model.toggleNotInterested(item)
        } label: {
            Label(
                model.library.isNotInterested(item.key) ? "Remove not interested" : "Not interested",
                systemImage: model.library.isNotInterested(item.key) ? "hand.thumbsup" : "hand.thumbsdown"
            )
        }

        Button(role: model.library.isNeverShowAgain(item.key) ? nil : .destructive) {
            model.toggleNeverShowAgain(item)
        } label: {
            Label(
                model.library.isNeverShowAgain(item.key) ? "Show in recommendations again" : "Never show this again",
                systemImage: model.library.isNeverShowAgain(item.key) ? "eye" : "eye.slash"
            )
        }

        if case .collection(let id) = swipeContext {
            Button(role: .destructive) {
                model.removeFromCollection(item, collectionID: id)
            } label: {
                Label("Remove from collection", systemImage: "trash")
            }
        }
    }
}

// MARK: - TileIconButton

struct TileIconButton: View {
    let systemName: String
    var tint: Color = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 28)
                .liquidGlass(cornerRadius: 14)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(systemName.contains("bookmark") ? "Save" : "Watched")
    }
}
