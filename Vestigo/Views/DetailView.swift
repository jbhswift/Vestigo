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
    @State var showCast = false
    @State var showCollections = false
    @State var selectedNestedItem: MediaItem?
    @State var isPosterPreviewPresented = false
    @State var showWatchedDatePopover = false
    @State var showingFriendRating = true
    #if canImport(CoreLocation)
    @StateObject var cinemaService = CinemaSearchService()
    @State var cinemaSelectedDate: Date = Calendar.current.startOfDay(for: Date())
    #endif

    var detail: MediaDetail? { model.detailsCache[item.key] }
    var providers: [StreamingOption]? { model.providerCache[item.key] }
    var isTMDbFallback: Bool { model.tmdbFallbackKeys.contains(item.key) }
    var visibleProviders: [StreamingOption]? {
        guard let filtered = providers?.filter({ !$0.serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }
        let subscribed = model.settings.subscribedServiceNames
        guard !subscribed.isEmpty else { return filtered }
        return filtered.sorted { a, b in
            let aIn = a.isSubscribed(in: subscribed)
            let bIn = b.isSubscribed(in: subscribed)
            if aIn != bIn { return aIn }
            return false
        }
    }
    var relatedMediaSections: [RelatedMediaSection] { model.relatedMediaCache[item.key] ?? [] }

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
                overviewSection
                actionSection
                castSection
                episodeSection
                similarSection
                trailerSection
                providersSection
                cinemasSection
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
