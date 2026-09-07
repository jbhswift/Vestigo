import SwiftUI
import Foundation

struct PickForMeResultsView: View {
    @ObservedObject var model: VestigoModel
    let results: [MediaItem]
    let resultIndex: Int
    let fallbackText: String?
    let onShowPrevious: () -> Void
    let onShowNext: () -> Void
    let onEditAnswers: () -> Void
    let onToggleNotInterested: (MediaItem) -> Void
    let onToggleNeverShowAgain: (MediaItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            let item = results[resultIndex]

            if let fallbackText {
                StatusBubble(title: "Not enough data to decide", text: fallbackText)
            }

            HStack(alignment: .top, spacing: 18) {
                Button {
                    model.selectedItem = item
                } label: {
                    PosterView(item: item, width: 164, height: 238, isFavourite: model.library.isFavourite(item))
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 10) {
                    Text(item.title)
                        .font(.title2.bold())
                        .lineLimit(3)

                    Text(resultMetadataText(for: item))
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Text(item.overview.isEmpty ? "No overview is available for this title." : item.overview)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(8)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }

            HStack(spacing: 10) {
                Button {
                    model.selectedItem = item
                } label: {
                    Label("Details", systemImage: "info.circle")
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .liquidGlass(cornerRadius: 24)
                }
                .buttonStyle(.plain)

                Button {
                    model.toggleWatchlist(item)
                } label: {
                    Image(systemName: model.library.isInWatchlist(item.key) ? "bookmark.fill" : "bookmark")
                        .font(.headline.bold())
                        .frame(width: 54, height: 48)
                        .liquidGlass(cornerRadius: 24)
                }
                .buttonStyle(.plain)

                Button {
                    model.toggleWatched(item)
                } label: {
                    Image(systemName: model.library.isWatched(item.key) ? "checkmark.circle.fill" : "checkmark.circle")
                        .font(.headline.bold())
                        .frame(width: 54, height: 48)
                        .liquidGlass(cornerRadius: 24)
                }
                .buttonStyle(.plain)
                .disabled(item.isUpcoming)
                .opacity(item.isUpcoming ? 0.45 : 1)
            }

            Button {
                onToggleNotInterested(item)
            } label: {
                Label(
                    model.library.isNotInterested(item.key) ? "Remove not interested" : "Not interested",
                    systemImage: model.library.isNotInterested(item.key) ? "hand.thumbsup" : "hand.thumbsdown"
                )
                .font(.headline.bold())
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .liquidGlass(cornerRadius: 24)
            }
            .buttonStyle(.plain)

            Button(role: model.library.isNeverShowAgain(item.key) ? nil : .destructive) {
                onToggleNeverShowAgain(item)
            } label: {
                Label(
                    model.library.isNeverShowAgain(item.key) ? "Show in recommendations again" : "Never show this again",
                    systemImage: model.library.isNeverShowAgain(item.key) ? "eye" : "eye.slash"
                )
                .font(.headline.bold())
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .liquidGlass(cornerRadius: 24)
            }
            .buttonStyle(.plain)

            Button {
                onEditAnswers()
            } label: {
                Label("Review answers", systemImage: "list.bullet.rectangle")
                    .font(.headline.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .liquidGlass(cornerRadius: 24)
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button {
                    onShowPrevious()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .liquidGlass(cornerRadius: 24)
                }
                .buttonStyle(.plain)
                .disabled(resultIndex == 0)
                .opacity(resultIndex == 0 ? 0.45 : 1)

                Button {
                    onShowNext()
                } label: {
                    Label(resultIndex == results.count - 1 ? "Retake" : "Next", systemImage: resultIndex == results.count - 1 ? "arrow.counterclockwise" : "chevron.right")
                        .font(.headline.bold())
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .liquidGlass(cornerRadius: 24)
                }
                .buttonStyle(.plain)
            }
        }
        .task(id: results[resultIndex].key) {
            await model.loadDetail(results[resultIndex])
        }
    }

    private func resultMetadataText(for item: MediaItem) -> String {
        var parts = [item.displayKindLabel, item.releaseDateReadable]

        if let ageRating = model.detailsCache[item.key]?.ageRating,
           !ageRating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(ageRating)
        }

        let ratingText = model.ratingDisplayText(for: item)
        if !ratingText.isEmpty {
            parts.append(ratingText)
        }
        return parts.joined(separator: " • ")
    }
}
