import SwiftUI
import SVGView

/// Renders a remote logo image, handling both raster formats (via UIImage, same as
/// AsyncImage would) and SVG (which SwiftUI's AsyncImage/UIImage cannot decode at
/// runtime — MoTN's provider logos are predominantly SVG wordmarks).
struct RemoteLogoView<Fallback: View>: View {
    let url: URL?
    let contentPadding: CGFloat
    @ViewBuilder var fallback: () -> Fallback

    @State private var svgNode: SVGNode?
    @State private var rasterImage: UIImage?

    private var isSVG: Bool {
        url?.pathExtension.lowercased() == "svg"
    }

    var body: some View {
        Group {
            if let svgNode {
                SVGView(svg: svgNode)
                    .aspectRatio(contentMode: .fit)
                    .padding(contentPadding)
            } else if let rasterImage {
                Image(uiImage: rasterImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(contentPadding)
            } else {
                fallback()
            }
        }
        .task(id: url) {
            svgNode = nil
            rasterImage = nil
            guard let url else { return }
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
            // Parse eagerly so a malformed/unsupported SVG (SVGView doesn't support every
            // feature — some MoTN logos use gradients/filters it can't parse) correctly
            // falls through to the fallback instead of silently rendering nothing.
            if isSVG {
                svgNode = SVGParser.parse(data: data)
            } else {
                rasterImage = UIImage(data: data)
            }
        }
    }
}
