import SwiftUI

// MARK: - Charts

struct ChartResultsView: View {
    let kind: MediaKind
    @ObservedObject var model: VestigoModel
    @State private var hasLoaded = false
    @State private var loadError: String?
    @Environment(\.imageRefreshToken) private var imageRefreshToken

    private var items: [MediaItem] {
        kind == .movie ? model.topRatedMovies : model.topRatedShows
    }

    var body: some View {
        BaseScreen(
            title: kind == .movie ? "Top 100 Movies" : "Top 100 Series",
            filter: .constant(.both),
            settings: model.settings,
            onRefresh: { await load() }
        ) {
            Text("Ranked by \(model.settings.preferredRatingSource.title) · Change in Settings")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let error = loadError {
                Text("Error: \(error)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            } else if items.isEmpty {
                LoadingBubble(title: "Building chart", text: "Loading chart…")
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(Array(items.prefix(100).enumerated()), id: \.element.key) { index, item in
                        ChartItemRow(rank: index + 1, item: item, model: model, imageRefreshToken: imageRefreshToken)
                    }
                }
            }
        }
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            Task { await load() }
        }
    }

    private func load() async {
        loadError = nil
        do {
            try await model.loadTopRatedThrowing(kind: kind)
        } catch is CancellationError {
            // Ignore — SwiftUI refresh gesture cancelled the task
        } catch let urlError as URLError where urlError.code == .cancelled {
            // Ignore — URLSession task cancelled by SwiftUI refresh lifecycle
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct ChartItemRow: View {
    let rank: Int
    let item: MediaItem
    @ObservedObject var model: VestigoModel
    let imageRefreshToken: Int
    @State private var showCollections = false

    private var posterURL: URL? {
        item.posterPath.flatMap { URL(string: "https://image.tmdb.org/t/p/w185\($0)") }
    }

    var body: some View {
        Button {
            model.selectedItem = item
        } label: {
            HStack(spacing: 14) {
                Text("\(rank)")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
                    .monospacedDigit()

                AsyncImage(url: posterURL?.refreshedImageURL(token: imageRefreshToken)) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(.white.opacity(0.1))
                    }
                }
                .frame(width: 44, height: 66)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    let ratingText = model.ratingDisplayText(for: item)
                    if !ratingText.isEmpty {
                        Text(ratingText)
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }

                    Text(item.releaseYearText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .liquidGlass(cornerRadius: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            MediaItemContextMenuActions(item: item, hideWatched: false, model: model, swipeContext: .none) {
                showCollections = true
            }
        }
        .sheet(isPresented: $showCollections) {
            AddToCollectionSheet(item: item, model: model)
        }
    }
}
