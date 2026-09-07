import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - MediaGridOrList

struct MediaGridOrList: View {
    let items: [MediaItem]
    let hideWatchedForUpcoming: Bool
    @ObservedObject var model: VestigoModel
    var swipeContext: SwipeContext = .none
    var mode: ViewMode = .tile
    var openItem: ((MediaItem) -> Void)? = nil

    var body: some View {
        content
    }

    @ViewBuilder private var content: some View {
        if items.isEmpty {
            emptyState
        } else if mode == .list {
            listContent
        } else {
            gridContent
        }
    }

    private var emptyState: some View {
        StatusBubble(title: "No results", text: "Nothing matched the current filter.")
    }

    private var listContent: some View {
        MediaList(items: items, model: model)
    }

    private var gridContent: some View {
        LazyVGrid(columns: gridColumns, spacing: 18) {
            ForEach(items) { item in
                MediaTile(item: item, hideWatched: hideWatchedForUpcoming, model: model, openItem: openItem, swipeContext: swipeContext)
            }
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 148), spacing: 14)]
    }
}

// MARK: - FullMediaListView

struct FullMediaListView: View {
    let title: String
    let items: [MediaItem]
    @ObservedObject var model: VestigoModel

    var body: some View {
        BaseScreen(title: title, filter: .constant(.both), settings: model.settings) {
            MediaGridOrList(items: items, hideWatchedForUpcoming: false, model: model)
        }
    }
}
