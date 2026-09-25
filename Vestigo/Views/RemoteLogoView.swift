import SwiftUI
import SVGView

enum RemoteLogoDisplayMode {
    case fit
    case fill
}

/// Renders a remote logo image, handling both raster formats and SVG. Some logo URLs
/// arrive without useful extensions, so SVG detection checks MIME type and response body too.
struct RemoteLogoView<Fallback: View>: View {
    let url: URL?
    let contentPadding: CGFloat
    let displayMode: RemoteLogoDisplayMode
    @ViewBuilder var fallback: () -> Fallback

    @State private var svgNode: SVGNode?
    @State private var rasterImage: UIImage?

    init(
        url: URL?,
        contentPadding: CGFloat,
        displayMode: RemoteLogoDisplayMode = .fit,
        @ViewBuilder fallback: @escaping () -> Fallback
    ) {
        self.url = url
        self.contentPadding = contentPadding
        self.displayMode = displayMode
        self.fallback = fallback
    }

    var body: some View {
        Group {
            if let svgNode {
                SVGView(svg: svgNode)
                    .aspectRatio(contentMode: displayMode.contentMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(contentPadding)
            } else if let rasterImage {
                Image(uiImage: rasterImage)
                    .resizable()
                    .aspectRatio(contentMode: displayMode.contentMode)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(contentPadding)
            } else {
                fallback()
            }
        }
        .task(id: url) {
            svgNode = nil
            rasterImage = nil
            guard let url else { return }
            guard let (data, response) = try? await URLSession.shared.data(from: url) else { return }

            if Self.isSVG(url: url, response: response, data: data) {
                svgNode = SVGParser.parse(data: data)
            } else if let image = UIImage(data: data) {
                rasterImage = displayMode == .fill ? image.trimmingTransparentPixels() : image
            }
        }
    }

    private static func isSVG(url: URL, response: URLResponse, data: Data) -> Bool {
        if url.pathExtension.lowercased() == "svg" { return true }
        if url.absoluteString.lowercased().hasPrefix("data:image/svg+xml") { return true }
        if response.mimeType?.lowercased().contains("svg") == true { return true }
        guard let prefix = String(data: data.prefix(160), encoding: .utf8)?.lowercased() else { return false }
        return prefix.contains("<svg")
    }
}

private extension RemoteLogoDisplayMode {
    var contentMode: ContentMode {
        switch self {
        case .fit: return .fit
        case .fill: return .fill
        }
    }
}

private extension UIImage {
    func trimmingTransparentPixels(alphaThreshold: UInt8 = 8) -> UIImage {
        guard let cgImage else { return self }

        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return self }

        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return self
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1

        for y in 0..<height {
            for x in 0..<width {
                let alpha = pixels[y * bytesPerRow + x * bytesPerPixel + 3]
                if alpha > alphaThreshold {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard maxX >= minX, maxY >= minY else { return self }
        guard minX > 0 || minY > 0 || maxX < width - 1 || maxY < height - 1 else { return self }
        guard let cropped = cgImage.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)) else {
            return self
        }
        return UIImage(cgImage: cropped, scale: scale, orientation: imageOrientation)
    }
}
