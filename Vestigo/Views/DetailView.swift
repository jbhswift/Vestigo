import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(MapKit)
import MapKit
#endif
#if canImport(CoreLocation)
import CoreLocation
#endif
#if canImport(WebKit)
import WebKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

// MARK: - Detail

struct DetailView: View {
    let item: MediaItem
    @ObservedObject var model: VestigoModel
    var allowsPersonSheet: Bool = true
    @Environment(\.imageRefreshToken) var imageRefreshToken
    @AppStorage("Vestigo.devMode") var devMode: Bool = false
    @State var showCast = false
    @State var showCollections = false
    @State var selectedNestedItem: MediaItem?
    @State var isPosterPreviewPresented = false
    @State var showWatchedDatePopover = false
    @State var showingFriendRating = true
    @State var providerLoadStartedAt: Date?
    @State var providerLoadElapsed: TimeInterval = 0
    @State var providerLoadFinishedElapsed: TimeInterval?
    #if canImport(CoreLocation)
    @StateObject var cinemaService = CinemaSearchService()
    @State var cinemaSelectedDate: Date = Calendar.current.startOfDay(for: Date())
    #endif

    var detail: MediaDetail? { model.detailsCache[item.key] }
    var providers: [StreamingOption]? { model.providerCache[item.key] }
    var isTMDbFallback: Bool { model.tmdbFallbackKeys.contains(item.key) }
    var visibleProviders: [StreamingOption]? {
        guard let filtered = providers?.filter({ !$0.serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }
        let collapsed = StreamingOption.collapsedForProviderDisplay(filtered)
        let subscribed = model.settings.subscribedServiceNames
        guard !subscribed.isEmpty else { return collapsed }
        return collapsed.sorted { a, b in
            let aIn = a.isSubscribed(in: subscribed)
            let bIn = b.isSubscribed(in: subscribed)
            if aIn != bIn { return aIn }
            return false
        }
    }
    var relatedMediaSections: [RelatedMediaSection] { model.relatedMediaCache[item.key] ?? [] }

    var isProviderTimingRunning: Bool {
        devMode && providers == nil && providerLoadStartedAt != nil && providerLoadFinishedElapsed == nil
    }

    var providerLoadTimingText: String? {
        guard devMode, let startedAt = providerLoadStartedAt else { return nil }
        if let providerLoadFinishedElapsed {
            return "Where to watch loaded in \(formattedProviderLoadTime(providerLoadFinishedElapsed))."
        }
        guard providers == nil else {
            let elapsed = max(providerLoadElapsed, Date().timeIntervalSince(startedAt))
            return "Where to watch loaded in \(formattedProviderLoadTime(elapsed))."
        }
        return "Where to watch loading \(formattedProviderLoadTime(max(providerLoadElapsed, 0)))."
    }

    enum ProviderAvailability { case available, paidOnly, unavailable }

    var providerAvailability: ProviderAvailability? {
        let subscribed = model.settings.subscribedServiceNames
        guard !subscribed.isEmpty, let options = providers else { return nil }
        let hasFree = options.contains {
            ["subscription", "sub", "free"].contains($0.type.lowercased()) && $0.isSubscribed(in: subscribed)
        }
        if hasFree { return .available }
        let hasPaid = options.contains {
            ["rent", "buy", "addon"].contains($0.type.lowercased()) && $0.isSubscribed(in: subscribed)
        }
        return hasPaid ? .paidOnly : .unavailable
    }
    var externalRatings: ExternalRatings? { model.externalRatingsCache[item.key] }

    var selectedPersonBinding: Binding<PersonSummary?> {
        Binding(
            get: { allowsPersonSheet ? model.selectedPerson : nil },
            set: { model.selectedPerson = $0 }
        )
    }

    var body: some View {
        detailSheetSurface
            .overlay {
                if isPosterPreviewPresented {
                    posterPreviewOverlay
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.18), value: isPosterPreviewPresented)
            .favouriteReplacementOverlay(model: model)
            .ratingPromptOverlay(model: model, suppressedItemKey: model.friendDetailContext == nil ? item.key : nil)
            .presentationBackground(.clear)
            .presentationCornerRadius(54)
            .task { await model.loadDetail(item) }
            .task(id: model.settings.streamingRegion) {
                async let tmdbLogos: Void = model.loadTMDbRegionProviders()
                async let regionCatalog: Void = model.loadRegionServiceCatalog()
                _ = await (tmdbLogos, regionCatalog)
            }
            .task(id: isProviderTimingRunning) {
                guard isProviderTimingRunning else { return }
                while isProviderTimingRunning && !Task.isCancelled {
                    providerLoadElapsed = Date().timeIntervalSince(providerLoadStartedAt ?? Date())
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
            .onAppear { updateProviderLoadTiming() }
            .onChange(of: providers != nil) { _, _ in updateProviderLoadTiming() }
            .onChange(of: devMode) { _, _ in updateProviderLoadTiming() }
            .onDisappear { model.friendDetailContext = nil }
            .sheet(isPresented: $showCollections) {
                AddToCollectionSheet(item: item, model: model)
            }
            .sheet(item: selectedPersonBinding) { person in
                PersonDetailView(person: person, model: model)
            }
            .sheet(item: $selectedNestedItem) { item in
                DetailView(item: item, model: model, allowsPersonSheet: allowsPersonSheet)
            }
    }

    var detailSheetSurface: some View {
        detailScroll
            .safeAreaInset(edge: .top, spacing: 0) {
                sheetGrabBar
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .sheetLiquidGlass(cornerRadius: 48)
            .ignoresSafeArea(edges: .bottom)
    }

    var sheetGrabBar: some View {
        Capsule()
            .fill(.white.opacity(0.46))
            .frame(width: 48, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .background(.clear)
    }

    var detailScroll: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                headerSection
                ratingSection
                detailButtons
                featuredSection
                overviewSection
                actionSection
                castSection
                episodeSection
                similarSection
                trailerSection
                cinemasSection
                providersSection
                relatedMediaSection
                soundtrackSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 110)
        }
        .scrollClipDisabled()
        .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        .scrollDismissesKeyboard(.immediately)
        .scrollIndicators(.hidden)
        .scrollViewTouchTuning(axis: .vertical)
    }

    func updateProviderLoadTiming() {
        guard devMode else {
            providerLoadStartedAt = nil
            providerLoadElapsed = 0
            providerLoadFinishedElapsed = nil
            return
        }

        if providers == nil {
            if providerLoadStartedAt == nil {
                providerLoadStartedAt = Date()
                providerLoadElapsed = 0
                providerLoadFinishedElapsed = nil
            }
        } else if let startedAt = providerLoadStartedAt, providerLoadFinishedElapsed == nil {
            let elapsed = Date().timeIntervalSince(startedAt)
            providerLoadElapsed = elapsed
            providerLoadFinishedElapsed = elapsed
        }
    }

    func formattedProviderLoadTime(_ elapsed: TimeInterval) -> String {
        String(format: "%.1fs", elapsed)
    }

    func openNestedItem(_ item: MediaItem) {
        selectedNestedItem = item
    }
}

// MARK: - Shared button style

struct DetailRowButton: View {
    let title: String
    let systemName: String
    var isEnabled = true
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button {
            if isEnabled { action() }
        } label: {
            Label(title, systemImage: systemName)
                .font(.subheadline.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .foregroundStyle(tint.map { AnyShapeStyle($0) } ?? (isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary.opacity(0.55))))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .liquidGlass(cornerRadius: 22)
                .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
