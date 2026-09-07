import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - MediaSection

struct MediaSection: View {
    let title: String
    let items: [MediaItem]
    let hideWatchedForUpcoming: Bool
    @ObservedObject var model: VestigoModel
    var oneLineOnly = true
    var openItem: ((MediaItem) -> Void)? = nil
    var openFull: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let openFull {
                Button {
                    openFull()
                } label: {
                    HStack(spacing: 8) {
                        Text(title)
                            .sectionTitle()

                        Spacer(minLength: 0)

                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text(title)
                    .sectionTitle()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if items.isEmpty {
                if model.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    StatusBubble(title: "Nothing here yet", text: "This section will fill after more data loads or after you rate more watched items.")
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(items.prefix(oneLineOnly ? 12 : items.count)) { item in
                            MediaTile(item: item, hideWatched: hideWatchedForUpcoming, model: model, openItem: openItem)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .scrollClipDisabled()
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
