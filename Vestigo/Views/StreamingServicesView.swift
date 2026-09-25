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

enum StreamingProviderCostFilter: String, CaseIterable, Identifiable {
    case paid = "Paid"
    case free = "Free"
    case both = "Both"

    var id: String { rawValue }
}

struct StreamingServicePickerItem: Identifiable {
    let id: String
    let selectionIDSet: Set<String>
    let displayName: String
    let hasFreeOption: Bool
    let hasPaidOption: Bool
    let iconLabel: String
    let brandColorHex: String
    let lightText: Bool
    let logoURL: URL?
    let logoDisplayMode: RemoteLogoDisplayMode
    let isAvailable: Bool

    func isSelected(in serviceNames: Set<String>) -> Bool {
        !selectionIDSet.isDisjoint(with: serviceNames)
    }

    func mergingAvailability(from lhs: StreamingServicePickerItem, and rhs: StreamingServicePickerItem) -> StreamingServicePickerItem {
        let mergedSelectionIDs = lhs.selectionIDSet.union(rhs.selectionIDSet)
        return StreamingServicePickerItem(
            id: Self.groupedSelectionID(from: mergedSelectionIDs) ?? id,
            selectionIDSet: mergedSelectionIDs,
            displayName: displayName,
            hasFreeOption: lhs.hasFreeOption || rhs.hasFreeOption,
            hasPaidOption: lhs.hasPaidOption || rhs.hasPaidOption,
            iconLabel: iconLabel,
            brandColorHex: brandColorHex,
            lightText: lightText,
            logoURL: logoURL,
            logoDisplayMode: logoDisplayMode,
            isAvailable: lhs.isAvailable || rhs.isAvailable
        )
    }

    private static func groupedSelectionID(from selectionIDs: Set<String>) -> String? {
        let tmdbIDs = selectionIDs
            .filter { $0.hasPrefix("tmdb:") }
            .flatMap { selectionID -> [Int] in
                let providerIDPart = selectionID.split(separator: ":").dropFirst().first.map(String.init) ?? ""
                return providerIDPart.split(separator: ",").compactMap { Int($0) }
            }
            .sorted()
        guard !tmdbIDs.isEmpty else { return nil }
        let name = selectionIDs
            .first { $0.hasPrefix("tmdb:") }?
            .split(separator: ":", maxSplits: 2)
            .dropFirst(2)
            .first
            .map(String.init) ?? "provider"
        return "tmdb:\(tmdbIDs.map(String.init).joined(separator: ",")):\(name)"
    }

    static func mergedCatalog(
        regionServiceCatalog: [RegionStreamingService],
        tmdbRegionProviders: [TMDbWatchProviderLogoDTO],
        tmdbGlobalProviders: [TMDbWatchProviderLogoDTO],
        includeUnavailable: Bool
    ) -> [StreamingServicePickerItem] {
        let availableProviderIDs = Set(tmdbRegionProviders.map(\.providerID))
        let tmdbSource = includeUnavailable ? mergedProviders(tmdbRegionProviders, tmdbGlobalProviders) : tmdbRegionProviders
        var items = tmdbSource.filter { !StreamingProviderNameNormalizer.isAddOnVariant($0.providerName) }.map { provider in
            item(provider: provider, regionServiceCatalog: regionServiceCatalog, isAvailable: availableProviderIDs.contains(provider.providerID))
        }

        let motnOnlyItems = regionServiceCatalog
            .filter { regionService in
                !items.contains { namesMatch($0.displayName, regionService.name) }
            }
            .map { regionService in item(regionService: regionService) }

        items.append(contentsOf: motnOnlyItems)
        return dedupedAndSorted(items)
    }

    private static func item(provider: TMDbWatchProviderLogoDTO, regionServiceCatalog: [RegionStreamingService], isAvailable: Bool) -> StreamingServicePickerItem {
        let knownService = knownService(for: provider)
        let regionMatch = regionServiceCatalog.first { regionService in
            exactNameMatch(provider.providerName, regionService.name) || knownService?.matches(regionService.name) == true
        }
        let displayName = knownService?.displayName ?? regionMatch?.name ?? provider.providerName
        let isFreeVariant = regionMatch?.isFree ?? knownService?.isFree ?? StreamingProviderNameNormalizer.isFreeProviderName(provider.providerName)

        return StreamingServicePickerItem(
            id: knownService?.id ?? provider.selectionID,
            selectionIDSet: [knownService?.id ?? provider.selectionID],
            displayName: displayName,
            hasFreeOption: isFreeVariant,
            hasPaidOption: !isFreeVariant,
            iconLabel: knownService?.iconLabel ?? initials(for: displayName),
            brandColorHex: regionMatch?.themeColorHex ?? knownService?.brandColorHex ?? "#3A3A3C",
            lightText: knownService?.lightText ?? true,
            logoURL: provider.logoURL ?? regionMatch?.logoURL.flatMap { URL(string: $0) },
            logoDisplayMode: provider.logoURL != nil ? .fill : .fit,
            isAvailable: isAvailable
        )
    }

    private static func item(regionService: RegionStreamingService) -> StreamingServicePickerItem {
        let knownService = KnownStreamingService.catalog.first { exactKnownServiceMatch($0, regionService.name) }
        let displayName = knownService?.displayName ?? regionService.name
        return StreamingServicePickerItem(
            id: knownService?.id ?? regionService.id,
            selectionIDSet: [knownService?.id ?? regionService.id],
            displayName: displayName,
            hasFreeOption: regionService.isFree || knownService?.isFree == true,
            hasPaidOption: !(regionService.isFree || knownService?.isFree == true),
            iconLabel: knownService?.iconLabel ?? initials(for: displayName),
            brandColorHex: regionService.themeColorHex ?? knownService?.brandColorHex ?? "#3A3A3C",
            lightText: knownService?.lightText ?? true,
            logoURL: regionService.logoURL.flatMap { URL(string: $0) },
            logoDisplayMode: .fit,
            isAvailable: true
        )
    }

    private static func mergedProviders(_ regionProviders: [TMDbWatchProviderLogoDTO], _ globalProviders: [TMDbWatchProviderLogoDTO]) -> [TMDbWatchProviderLogoDTO] {
        var providersByID: [Int: TMDbWatchProviderLogoDTO] = [:]
        for provider in globalProviders { providersByID[provider.providerID] = provider }
        for provider in regionProviders { providersByID[provider.providerID] = provider }
        return Array(providersByID.values)
    }

    private static func dedupedAndSorted(_ items: [StreamingServicePickerItem]) -> [StreamingServicePickerItem] {
        var itemsByName: [String: StreamingServicePickerItem] = [:]
        for item in items {
            let key = StreamingProviderNameNormalizer.dedupName(item.displayName)
            guard let existing = itemsByName[key] else {
                itemsByName[key] = item
                continue
            }
            let preferred: StreamingServicePickerItem
            if item.isAvailable && !existing.isAvailable {
                preferred = item
            } else if item.logoURL != nil && existing.logoURL == nil {
                preferred = item
            } else if StreamingProviderNameNormalizer.offerQualifierScore(item.displayName) < StreamingProviderNameNormalizer.offerQualifierScore(existing.displayName) {
                preferred = item
            } else {
                preferred = existing
            }
            itemsByName[key] = preferred.mergingAvailability(from: existing, and: item)
        }
        return itemsByName.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private static func knownService(for provider: TMDbWatchProviderLogoDTO) -> KnownStreamingService? {
        KnownStreamingService.catalog.first { service in
            service.tmdbProviderID == provider.providerID || exactKnownServiceMatch(service, provider.providerName)
        }
    }

    private static func exactKnownServiceMatch(_ service: KnownStreamingService, _ name: String) -> Bool {
        let normalized = StreamingProviderNameNormalizer.normalizedName(name)
        if StreamingProviderNameNormalizer.normalizedName(service.id) == normalized || StreamingProviderNameNormalizer.normalizedName(service.displayName) == normalized { return true }
        return service.aliases.contains { StreamingProviderNameNormalizer.normalizedName($0) == normalized }
    }

    private static func exactNameMatch(_ lhs: String, _ rhs: String) -> Bool {
        StreamingProviderNameNormalizer.normalizedName(lhs) == StreamingProviderNameNormalizer.normalizedName(rhs)
    }

    private static func namesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let left = StreamingProviderNameNormalizer.normalizedName(lhs)
        let right = StreamingProviderNameNormalizer.normalizedName(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left.contains(right) || right.contains(left)
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
    @State private var searchText = ""
    @State private var costFilter: StreamingProviderCostFilter = .both
    @State private var showsUnavailableProviders = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    private var mergedCatalog: [StreamingServicePickerItem] {
        StreamingServicePickerItem.mergedCatalog(
            regionServiceCatalog: model.regionServiceCatalog,
            tmdbRegionProviders: model.tmdbRegionProviders,
            tmdbGlobalProviders: model.tmdbGlobalProviders,
            includeUnavailable: showsUnavailableProviders
        )
    }

    private var visibleCatalog: [StreamingServicePickerItem] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return mergedCatalog.filter { service in
            let matchesCost: Bool = {
                switch costFilter {
                case .paid: return service.hasPaidOption
                case .free: return service.hasFreeOption
                case .both: return true
                }
            }()
            guard matchesCost else { return false }
            guard !trimmedSearch.isEmpty else { return true }
            return service.displayName.localizedCaseInsensitiveContains(trimmedSearch)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            let subscribed = model.settings.subscribedServiceNames

            filterControls

            if model.tmdbRegionProviders.isEmpty && model.regionServiceCatalog.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
            } else {
                serviceGrid(services: visibleCatalog, subscribed: subscribed)
            }

            if !subscribed.isEmpty {
                Button("Clear all") {
                    model.settings.subscribedServiceNames.removeAll()
                    model.saveSettings()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .task(id: model.settings.streamingRegion) {
            await model.loadStreamingServiceCatalog()
        }
        .task(id: showsUnavailableProviders) {
            guard showsUnavailableProviders else { return }
            await model.loadTMDbGlobalProviders()
        }
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Search providers", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                showsUnavailableProviders.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showsUnavailableProviders ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(showsUnavailableProviders ? model.settings.accentColor : .secondary)
                    Text("Show unavailable providers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(.leading, 2)

            Picker("Provider type", selection: $costFilter) {
                ForEach(StreamingProviderCostFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func toggleSubscription(for service: StreamingServicePickerItem) {
        if service.isSelected(in: model.settings.subscribedServiceNames) {
            model.settings.subscribedServiceNames.subtract(service.selectionIDSet)
        } else {
            model.settings.subscribedServiceNames.formUnion(service.selectionIDSet)
        }
        model.saveSettings()
    }

    @ViewBuilder
    private func serviceGrid(services: [StreamingServicePickerItem], subscribed: Set<String>) -> some View {
        LazyVGrid(columns: columns, spacing: 20) {
            ForEach(services) { service in
                ServiceIconButton(
                    service: service,
                    isSelected: service.isSelected(in: subscribed),
                    accentColor: model.settings.accentColor
                ) {
                    toggleSubscription(for: service)
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

    private var tileFill: Color {
        service.logoURL == nil ? Color(hex: service.brandColorHex) : Color(red: 0.05, green: 0.055, blue: 0.065)
    }

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

                VStack(spacing: 2) {
                    Text(service.displayName)
                        .font(.caption2)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    if service.hasFreeOption && service.hasPaidOption {
                        Text("Free + Paid")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: iconSize + 10)
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var iconTile: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(tileFill)
            .frame(width: iconSize, height: iconSize)
            .overlay {
                if let logoURL = service.logoURL {
                    RemoteLogoView(
                        url: logoURL,
                        contentPadding: service.logoDisplayMode == .fill ? 0 : 5,
                        displayMode: service.logoDisplayMode
                    ) {
                        textLabel
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
