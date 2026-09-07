import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Remote Image Memory Cache

final class RemoteImageMemoryCache {
    static let shared = RemoteImageMemoryCache()
    private var images: [URL: PlatformImage] = [:]

    func image(for url: URL) -> PlatformImage? {
        images[url]
    }

    func setImage(_ image: PlatformImage, for url: URL) {
        images[url] = image
    }
}

// MARK: - Cached Async Image (UIKit)

#if canImport(UIKit)
struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    @ViewBuilder let content: (Image) -> Content
    @ViewBuilder let placeholder: () -> Placeholder
    @State private var uiImage: UIImage?

    var body: some View {
        Group {
            if let uiImage {
                content(Image(uiImage: uiImage))
            } else {
                placeholder()
            }
        }
        .task(id: url?.absoluteString) {
            await load()
        }
    }

    private func load() async {
        guard let url else { return }
        if let cached = ImageCache.shared[url] {
            uiImage = cached
            return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let raw = UIImage(data: data) else { return }
        let decoded = await Task.detached(priority: .userInitiated) {
            raw.preparingForDisplay() ?? raw
        }.value
        guard !Task.isCancelled else { return }
        ImageCache.shared[url] = decoded
        uiImage = decoded
    }
}
#endif

// MARK: - Remote Image View

struct RemoteImageView: View {
    let url: URL?
    let fallback: AnyView
    @State private var platformImage: PlatformImage?
    @State private var loadedURL: URL?

    var body: some View {
        ZStack {
            if let platformImage {
                platformImageView(platformImage)
            } else {
                fallback
            }
        }
        .task(id: url) {
            await loadImage()
        }
    }

    @ViewBuilder
    private func platformImageView(_ image: PlatformImage) -> some View {
#if canImport(UIKit)
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
#elseif canImport(AppKit)
        Image(nsImage: image)
            .resizable()
            .scaledToFill()
#endif
    }

    @MainActor
    private func setLoadedImage(_ image: PlatformImage?, for url: URL?) {
        platformImage = image
        loadedURL = url
    }

    private func loadImage() async {
        guard let url else {
            setLoadedImage(nil, for: nil)
            return
        }

        if loadedURL == url, platformImage != nil {
            return
        }

        if let cachedImage = RemoteImageMemoryCache.shared.image(for: url) {
            setLoadedImage(cachedImage, for: url)
            return
        }

        do {
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 20)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                setLoadedImage(nil, for: url)
                return
            }
            guard (200...299).contains(httpResponse.statusCode) else {
                setLoadedImage(nil, for: url)
                return
            }
            guard let image = PlatformImage(data: data) else {
                setLoadedImage(nil, for: url)
                return
            }
            RemoteImageMemoryCache.shared.setImage(image, for: url)
            setLoadedImage(image, for: url)
        } catch {
            setLoadedImage(nil, for: url)
        }
    }
}
