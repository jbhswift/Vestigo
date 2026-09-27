import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Tour data

struct TourStep {
    let id: Int
    let icon: String
    // Assets: tour_detail, tour_longpress, tour_search_charts, tour_pickforme, tour_settings
    let imageName: String?
    // When set, imageName and imageName2 are stacked vertically (top then bottom).
    let imageName2: String?
    // Custom-cropped composites (not full-device screenshots) size at their own natural
    // aspect ratio instead of the device screenshot ratio.
    let isCustomComposite: Bool
    let title: String
    let body: String

    init(id: Int, icon: String, imageName: String?, imageName2: String? = nil, isCustomComposite: Bool = false, title: String, body: String) {
        self.id = id
        self.icon = icon
        self.imageName = imageName
        self.imageName2 = imageName2
        self.isCustomComposite = isCustomComposite
        self.title = title
        self.body = body
    }
}

extension TourStep {
    static let all: [TourStep] = [
        TourStep(
            id: 0,
            icon: "popcorn.fill",
            imageName: nil,
            title: "Welcome to Vestigo",
            body: "Track and find your favourite movies and TV shows. The app uses your data to give you the best results."
        ),
        TourStep(
            id: 1,
            icon: "info.circle.fill",
            imageName: "tour_detail",
            title: "Tap any title for the full picture",
            body: "From an item's detail view, you can see more information about an item and mark it watched, save it, rate it, and more. You can also see where it is streaming and even where you can see it in cinemas nearby."
        ),
        TourStep(
            id: 2,
            icon: "hand.tap.fill",
            imageName: "tour_longpress",
            title: "Long-press for quick actions",
            body: "Long-press any poster to bring up a quick actions menu where you can also mark items as not interested or even to never show again. If you ever change your mind, you can find your banlist in data settings."
        ),
        TourStep(
            id: 3,
            icon: "magnifyingglass",
            imageName: "tour_search_charts",
            isCustomComposite: true,
            title: "Search tab",
            body: "Browse genres and explore all-time charts for movies and series to help you find what you're looking for."
        ),
        TourStep(
            id: 4,
            icon: "sparkles",
            imageName: "tour_pickforme",
            title: "Pick For Me",
            body: "Use Pick For Me in the Home tab to get recommendations based on a set of questions. You can filter by mood, rating, streaming services, and more."
        ),
        TourStep(
            id: 5,
            icon: "gearshape.fill",
            imageName: "tour_settings",
            title: "Adjusting settings",
            body: "Tap the gear icon in the top right of the Home tab to configure streaming services, tune content filters, and customise carousels."
        )
    ]
}

// MARK: - Main sheet

struct OnboardingTourView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var currentStep = 0

    private let steps = TourStep.all
    private var isLastStep: Bool { currentStep == steps.count - 1 }

    var body: some View {
        TabView(selection: $currentStep) {
            ForEach(steps, id: \.id) { step in
                TourStepPageView(step: step)
                    .tag(step.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .safeAreaInset(edge: .top, spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.46))
                .frame(width: 48, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(.clear)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            tourBottomBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheetLiquidGlass(cornerRadius: 48)
        .ignoresSafeArea(edges: .bottom)
        .presentationBackground(.clear)
        .presentationCornerRadius(54)
        .presentationDetents([.large])
    }

    private var tourBottomBar: some View {
        VStack(spacing: 14) {
            // Page indicator dots
            HStack(spacing: 7) {
                ForEach(steps.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == currentStep ? Color.primary : Color.secondary.opacity(0.3))
                        .frame(width: index == currentStep ? 22 : 7, height: 7)
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: currentStep)
                }
            }

            // Back | Next / Get Started (50/50 split)
            HStack(spacing: 12) {
                if currentStep > 0 {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            currentStep -= 1
                        }
                    } label: {
                        Text("Back")
                            .font(.headline.bold())
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .liquidGlass(cornerRadius: 26)
                    }
                    .buttonStyle(.plain)
                    .transition(.asymmetric(
                        insertion: .move(edge: .leading).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }

                if isLastStep {
                    Button {
                        dismiss()
                    } label: {
                        Text("Get Started")
                            .font(.headline.bold())
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .liquidGlass(cornerRadius: 26)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                            currentStep += 1
                        }
                    } label: {
                        Text("Next")
                            .font(.headline.bold())
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .liquidGlass(cornerRadius: 26)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: currentStep)
        }
        .padding(.top, 14)
        .padding(.bottom, 32)
        .background(.clear)
    }
}

// MARK: - Step page

private struct TourStepPageView: View {
    let step: TourStep

    var body: some View {
        VStack(spacing: 0) {
            stepHero
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.horizontal, 16)
                .padding(.top, 8)

            textBlock
                .padding(.horizontal, 24)
                .padding(.top, 18)
                .padding(.bottom, 10)
        }
    }

    private var textBlock: some View {
        VStack(spacing: 8) {
            Text(step.title)
                .font(.title3.bold())
                .multilineTextAlignment(.center)

            Text(step.body)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // iPhone 16e screenshot pixel dimensions (1170 x 2532) — used to size the rounded
    // box so it hugs the actual fitted image instead of the raw GeometryReader rect,
    // which can be letterboxed if its aspect ratio doesn't match the screenshot's.
    private let deviceAspectRatio: CGFloat = 1170.0 / 2532.0

    private func fittedSize(in available: CGSize) -> CGSize {
        let widthFromHeight = available.height * deviceAspectRatio
        if widthFromHeight <= available.width {
            return CGSize(width: widthFromHeight, height: available.height)
        } else {
            return CGSize(width: available.width, height: available.width / deviceAspectRatio)
        }
    }

    @ViewBuilder
    private var stepHero: some View {
        if step.isCustomComposite, let top = step.imageName, assetExists(top) {
            // Custom-cropped composites (not full-device screenshots) — use their own
            // natural aspect ratio at full width rather than the device ratio.
            VStack(spacing: 10) {
                tourImageNatural(top)
                if let bottom = step.imageName2, assetExists(bottom) {
                    tourImageNatural(bottom)
                }
            }
        } else if let imageName = step.imageName, assetExists(imageName) {
            GeometryReader { geo in
                tourImage(imageName, size: fittedSize(in: geo.size))
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        } else if step.id == 0, let appIcon = appIconImage {
            appIcon
                .resizable()
                .scaledToFit()
                .frame(width: 200, height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 44, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 44, style: .continuous)
                        .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.3), radius: 24, x: 0, y: 10)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(width: 140, height: 140)
                Image(systemName: step.icon)
                    .font(.system(size: 60, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func tourImage(_ name: String, size: CGSize) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 8)
    }

    private func tourImageNatural(_ name: String) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(.white.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 20, x: 0, y: 8)
    }

    private var appIconImage: Image? {
        #if canImport(UIKit)
        // AppIcon is an "App Icon" asset set, not a plain imageset — UIImage(named: "AppIcon")
        // reliably returns nil for those. Resolve the actual compiled icon file via Info.plist instead.
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let lastFile = files.last,
           let uiImage = UIImage(named: lastFile) {
            return Image(uiImage: uiImage)
        }
        if let uiImage = UIImage(named: "AppIcon") {
            return Image(uiImage: uiImage)
        }
        return nil
        #else
        return nil
        #endif
    }

    private func assetExists(_ name: String) -> Bool {
        #if canImport(UIKit)
        return UIImage(named: name) != nil
        #elseif canImport(AppKit)
        return NSImage(named: name) != nil
        #else
        return false
        #endif
    }
}
