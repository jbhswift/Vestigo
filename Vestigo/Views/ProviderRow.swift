import SwiftUI
import Foundation

// MARK: - ProviderRow

struct ProviderRow: View {
    let option: StreamingOption
    let regionServiceCatalog: [RegionStreamingService]
    let tmdbProviderLogos: [TMDbWatchProviderLogoDTO]
    @Environment(\.openURL) private var openURL
    @Environment(\.imageRefreshToken) private var imageRefreshToken

    private var tappableURL: URL? {
        option.tappableURL
    }

    private var matchedRegionService: RegionStreamingService? {
        option.matchedRegionService(in: regionServiceCatalog)
    }

    private var matchedTMDbProviderLogo: TMDbWatchProviderLogoDTO? {
        if let providerID = option.providerID {
            return tmdbProviderLogos.first { $0.providerID == providerID }
        }
        if let tmdbID = option.matchedCatalogService?.tmdbProviderID,
           let provider = tmdbProviderLogos.first(where: { $0.providerID == tmdbID }) {
            return provider
        }
        return tmdbProviderLogos.first { provider in
            StreamingProviderNameNormalizer.normalizedName(provider.providerName) == StreamingProviderNameNormalizer.normalizedName(option.displayServiceName)
        }
    }

    var body: some View {
        Button {
            guard let tappableURL else { return }
            openURL(tappableURL)
        } label: {
            HStack(spacing: 12) {
                providerLogo

                VStack(alignment: .leading, spacing: 3) {
                    Text(option.cleanedServiceName)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text(option.cleanedAvailabilityLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                if tappableURL != nil {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: 22)
        .opacity(tappableURL == nil ? 0.72 : 1.0)
        .appScrollTouchSafe()
    }

    private var providerLogo: some View {
        let catalogService = option.matchedCatalogService
        let tmdbLogoURL = option.tmdbLogoURL ?? matchedTMDbProviderLogo?.logoURL
        let logoURL = tmdbLogoURL ?? option.logoURL(regionServiceCatalog: regionServiceCatalog)
        let tileColor: Color = {
            if logoURL != nil { return Color(red: 0.05, green: 0.055, blue: 0.065) }
            if let hex = matchedRegionService?.themeColorHex { return Color(hex: hex) }
            if let hex = catalogService?.brandColorHex { return Color(hex: hex) }
            return .white.opacity(0.13)
        }()
        let logoDisplayMode = tmdbLogoURL == nil ? RemoteLogoDisplayMode.fit : .fill
        let logoPadding: CGFloat = {
            if tmdbLogoURL != nil { return 0 }
            return logoURL?.host(percentEncoded: false) == "www.google.com" ? 8 : 4
        }()

        return ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tileColor)

            if let url = logoURL {
                RemoteLogoView(
                    url: url.refreshedImageURL(token: imageRefreshToken),
                    contentPadding: logoPadding,
                    displayMode: logoDisplayMode
                ) {
                    providerFallbackText(lightText: catalogService?.lightText ?? true)
                }
            } else {
                providerFallbackText(lightText: catalogService?.lightText ?? true)
            }
        }
        .frame(width: 52, height: 52)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func providerFallbackText(lightText: Bool) -> some View {
        Text(option.serviceShort)
            .font(.caption.bold())
            .foregroundStyle(lightText ? Color.white : Color.black)
    }
}

extension StreamingOption {
    static func collapsedForProviderDisplay(_ options: [StreamingOption]) -> [StreamingOption] {
        var optionsByProvider: [String: StreamingOption] = [:]
        var orderedKeys: [String] = []

        for option in options {
            let key = StreamingProviderNameNormalizer.dedupName(option.displayServiceName)
            guard !key.isEmpty else { continue }

            guard let existing = optionsByProvider[key] else {
                optionsByProvider[key] = option
                orderedKeys.append(key)
                continue
            }

            optionsByProvider[key] = preferredProviderDisplayOption(existing, option)
        }

        return orderedKeys.compactMap { optionsByProvider[$0] }
    }

    private static func preferredProviderDisplayOption(_ lhs: StreamingOption, _ rhs: StreamingOption) -> StreamingOption {
        if lhs.isAddOnRoute != rhs.isAddOnRoute {
            return lhs.isAddOnRoute ? rhs : lhs
        }

        if lhs.tmdbLogoURL == nil && rhs.tmdbLogoURL != nil { return rhs }
        if lhs.tmdbLogoURL != nil && rhs.tmdbLogoURL == nil { return lhs }
        return lhs.displayAvailabilityRank <= rhs.displayAvailabilityRank ? lhs : rhs
    }

    var cleanedServiceName: String {
        let trimmed = (matchedCatalogService?.displayName ?? displayServiceName).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Unknown service" : trimmed
    }

    var cleanedAvailabilityLine: String {
        let parts = [cleanedTypeText, cleanedPriceText, cleanedQualityText]
            .compactMap { $0 }

        if parts.isEmpty {
            return "Availability details not provided"
        }

        return parts.joined(separator: " • ")
    }

    var dialogTitle: String {
        "\(cleanedServiceName) - \(cleanedAvailabilityLine)"
    }

    var tappableURL: URL? {
        guard let rawURL = openURL?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty else {
            return nil
        }
        return URL(string: rawURL)
    }

    private var cleanedTypeText: String? {
        let trimmed = type.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.isUnknownPlaceholder else { return nil }
        return trimmed.capitalized
    }

    private var cleanedPriceText: String? {
        let trimmed = priceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.isUnknownPlaceholder else { return nil }
        return trimmed
    }

    private var cleanedQualityText: String? {
        let trimmed = qualityText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.isUnknownPlaceholder else { return nil }
        return trimmed
    }

    var matchedCatalogService: KnownStreamingService? {
        KnownStreamingService.catalog.first { $0.matches(displayServiceName) }
    }

    func matchedRegionService(in catalog: [RegionStreamingService]) -> RegionStreamingService? {
        let normalized = StreamingProviderNameNormalizer.normalizedName(displayServiceName)
        return catalog.first { service in
            let name = StreamingProviderNameNormalizer.normalizedName(service.name)
            return normalized.contains(name) || name.contains(normalized)
        }
    }

    func logoURL(regionServiceCatalog: [RegionStreamingService]) -> URL? {
        if let tmdbLogoURL { return tmdbLogoURL }

        let regionMatch = matchedRegionService(in: regionServiceCatalog)
        if let logoURL = regionMatch?.logoURL.flatMap({ URL(string: $0) }) {
            return logoURL
        }

        return nil
    }

    var tmdbLogoURL: URL? {
        guard let logoPath, !logoPath.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w154\(logoPath)")
    }

    var displayServiceName: String {
        let baseName = StreamingProviderNameNormalizer.baseProviderName(from: serviceName)
        return baseName.isEmpty ? serviceName : baseName
    }

    private var isAddOnRoute: Bool {
        let normalizedType = type.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return ["addon", "add-on", "add_on"].contains(normalizedType)
            || StreamingProviderNameNormalizer.isAddOnVariant(serviceName)
    }

    private var displayAvailabilityRank: Int {
        switch type.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "subscription", "sub", "free": return 0
        case "addon", "add-on", "add_on": return 1
        case "rent", "rental": return 2
        case "buy", "purchase": return 3
        default: return 4
        }
    }
}
