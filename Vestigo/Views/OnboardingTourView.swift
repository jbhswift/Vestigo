import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Tour data

struct TourStep {
    let id: Int
    let icon: String
    // Add a same-named image asset to the asset catalog to replace the icon fallback.
    // Expected names: tour_detail, tour_longpress, tour_search, tour_pickforme, tour_settings
    let imageName: String?
    let title: String
    let body: String
}

extension TourStep {
    static let all: [TourStep] = [
        TourStep(
            id: 0,
            icon: "popcorn.fill",
            imageName: nil,
            title: "Welcome to Vestigo",
            body: "Your complete guide to movies and TV. Track what you've watched, discover what's next, and share your taste with friends."
        ),
        TourStep(
            id: 1,
            icon: "info.circle.fill",
            imageName: "tour_detail",
            title: "Tap any title for the full picture",
            body: "Streaming availability, cast, ratings, trailers, related titles, and more. Mark it watched and rate it right from here."
        ),
        TourStep(
            id: 2,
            icon: "hand.tap.fill",
            imageName: "tour_longpress",
            title: "Long-press for quick actions",
            body: "Long-press any poster to instantly save it, mark a favourite, or tell Vestigo you're not interested — it learns from every signal."
        ),
        TourStep(
            id: 3,
            icon: "magnifyingglass",
            imageName: "tour_search",
            title: "Search tab",
            body: "Browse genres, explore all-time charts, or tap \"Don't know the name?\" to describe what you're thinking of and Vestigo will find it."
        ),
        TourStep(
            id: 4,
            icon: "sparkles",
            imageName: "tour_pickforme",
            title: "Pick For Me",
            body: "Tap Pick For Me on the Home tab for AI-powered recommendations tailored to your mood and your streaming services."
        ),
        TourStep(
            id: 5,
            icon: "gearshape.fill",
            imageName: "tour_settings",
            title: "Settings make it yours",
            body: "Tap the gear icon on Home to set up streaming services, tune content filters, and customise your home carousels. The more you configure, the smarter Vestigo gets."
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
        ZStack(alignment: .topTrailing) {
            TabView(selection: $currentStep) {
                ForEach(steps, id: \.id) { step in
                    TourStepPageView(step: step)
                        .tag(step.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Skip button — liquidGlass pill, hidden on welcome step
            Button {
                dismiss()
            } label: {
                Text("Skip")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .liquidGlass(cornerRadius: 17)
            }
            .buttonStyle(.plain)
            .padding(.top, 16)
            .padding(.trailing, 18)
            .opacity(currentStep > 0 ? 1 : 0)
            .allowsHitTesting(currentStep > 0)
            .animation(.easeInOut(duration: 0.2), value: currentStep)
        }
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
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(Color.blue, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
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
            Spacer(minLength: 24)

            stepHero
                .padding(.horizontal, 24)

            Spacer(minLength: 24)

            VStack(spacing: 12) {
                Text(step.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(step.body)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 28)

            Spacer()
        }
    }

    @ViewBuilder
    private var stepHero: some View {
        if let imageName = step.imageName, assetExists(imageName) {
            Image(imageName)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 320)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
        } else if step.id == 0, let appIcon = appIconImage {
            appIcon
                .resizable()
                .frame(width: 110, height: 110)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 6)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .frame(width: 140, height: 140)
                Image(systemName: step.icon)
                    .font(.system(size: 60, weight: .semibold))
                    .foregroundStyle(.primary)
            }
        }
    }

    private var appIconImage: Image? {
        #if canImport(UIKit)
        guard let uiImage = UIImage(named: "AppIcon") else { return nil }
        return Image(uiImage: uiImage)
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
