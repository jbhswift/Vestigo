import SwiftUI
import Foundation

// MARK: - Streaming Services Setup Sheet

struct StreamingServicesSetupSheet: View {
    @ObservedObject var model: VestigoModel
    let isOnboarding: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .center) {
                    if isOnboarding {
                        Image(systemName: "play.tv.fill")
                            .font(.title3)
                            .foregroundStyle(model.settings.accentColor)
                    }
                    Text(isOnboarding ? "Your Streaming Services" : "Streaming Services")
                        .font(.title2.bold())
                    Spacer()
                    if isOnboarding {
                        Button("Done") { model.completeStreamingSetup() }
                            .fontWeight(.semibold)
                            .foregroundStyle(model.settings.accentColor)
                    }
                }

                if isOnboarding {
                    Text("Select what you subscribe to. Vestigo will put these at the top of where-to-watch lists and can alert you when your saved titles arrive on them.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                StreamingServicesPicker(model: model)
            }
            .padding(18)
            .padding(.bottom, 110)
        }
        .scrollClipDisabled()
        .scrollDismissesKeyboard(.immediately)
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            Capsule()
                .fill(.white.opacity(0.46))
                .frame(width: 48, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 8)
                .background(.clear)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheetLiquidGlass(cornerRadius: 48)
        .ignoresSafeArea(edges: .bottom)
        .presentationBackground(.clear)
        .presentationCornerRadius(54)
    }
}

// MARK: - Picker item

/// Unified shape for the "Manage streaming services" grid, merging the hand-curated
/// `KnownStreamingService.catalog` (which carries TMDB provider IDs) with whatever else
/// MoTN knows about for the current region (which doesn't). Static entries take priority
/// on name collisions so curated TMDB mappings/colors are never shadowed by a dynamic entry.
struct StreamingServicePickerItem: Identifiable {
    let id: String
    let displayName: String
    let isFree: Bool
    let iconLabel: String
    let brandColorHex: String
    let lightText: Bool
    let logoURL: URL?

    static func mergedCatalog(regionServiceCatalog: [RegionStreamingService]) -> [StreamingServicePickerItem] {
        let staticItems = KnownStreamingService.catalog.map { service in
            StreamingServicePickerItem(
                id: service.id,
                displayName: service.displayName,
                isFree: service.isFree,
                iconLabel: service.iconLabel,
                brandColorHex: service.brandColorHex,
                lightText: service.lightText,
                logoURL: nil
            )
        }

        let dynamicItems = regionServiceCatalog
            .filter { dynamic in !KnownStreamingService.catalog.contains { $0.matches(dynamic.name) } }
            .map { dynamic in
                StreamingServicePickerItem(
                    id: dynamic.id,
                    displayName: dynamic.name,
                    isFree: dynamic.isFree,
                    iconLabel: Self.initials(for: dynamic.name),
                    brandColorHex: dynamic.themeColorHex ?? "#3A3A3C",
                    lightText: true,
                    logoURL: dynamic.logoURL.flatMap(URL.init(string:))
                )
            }

        return staticItems + dynamicItems
    }

    private static func initials(for name: String) -> String {
        let letters = name
            .split { !$0.isLetter && !$0.isNumber }
            .compactMap { $0.first }
            .prefix(2)
            .map { String($0).uppercased() }
            .joined()
        return letters.isEmpty ? String(name.prefix(2)).uppercased() : letters
    }
}

struct StreamingServicesPicker: View {
    @ObservedObject var model: VestigoModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    private var mergedCatalog: [StreamingServicePickerItem] {
        StreamingServicePickerItem.mergedCatalog(regionServiceCatalog: model.regionServiceCatalog)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            let subscribed = model.settings.subscribedServiceNames
            let catalog = mergedCatalog
            let paid = catalog.filter { !$0.isFree }
            let free = catalog.filter { $0.isFree }

            serviceGrid(title: "Subscription", services: paid, subscribed: subscribed)
            serviceGrid(title: "Free", services: free, subscribed: subscribed)

            if !subscribed.isEmpty {
                Button("Clear all") {
                    for item in catalog {
                        model.settings.subscribedServiceNames.remove(item.id)
                    }
                    model.saveSettings()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func serviceGrid(title: String, services: [StreamingServicePickerItem], subscribed: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .tracking(0.5)
                .padding(.leading, 2)

            LazyVGrid(columns: columns, spacing: 20) {
                ForEach(services) { service in
                    ServiceIconButton(
                        service: service,
                        isSelected: subscribed.contains(service.id),
                        accentColor: model.settings.accentColor
                    ) {
                        model.toggleSubscribedService(service.id)
                    }
                }
            }
        }
    }
}

struct ServiceIconButton: View {
    let service: StreamingServicePickerItem
    let isSelected: Bool
    let accentColor: Color
    let action: () -> Void

    private let iconSize: CGFloat = 72

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    iconTile
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(isSelected ? accentColor : Color.white.opacity(0.08), lineWidth: isSelected ? 3 : 1)
                        )

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(.white, accentColor)
                            .offset(x: 8, y: -8)
                    }
                }

                Text(service.displayName)
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: iconSize + 10)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var iconTile: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(hex: service.brandColorHex))
            .frame(width: iconSize, height: iconSize)
            .overlay {
                if let logoURL = service.logoURL {
                    AsyncImage(url: logoURL) { phase in
                        if case .success(let image) = phase {
                            image
                                .resizable()
                                .scaledToFill()
                        } else {
                            textLabel
                        }
                    }
                } else {
                    textLabel
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var textLabel: some View {
        Text(service.iconLabel)
            .font(.system(size: service.iconLabel.count > 4 ? 13 : 16, weight: .heavy, design: .rounded))
            .foregroundStyle(service.lightText ? Color.white : Color.black)
            .minimumScaleFactor(0.6)
            .padding(6)
    }
}
