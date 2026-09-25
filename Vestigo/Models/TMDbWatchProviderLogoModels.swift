import Foundation

nonisolated struct TMDbWatchProviderListResponse: Decodable, Sendable {
    let results: [TMDbWatchProviderLogoDTO]
}

nonisolated struct TMDbWatchProviderLogoDTO: Decodable, Sendable, Identifiable, Hashable {
    let providerID: Int
    let providerName: String
    let logoPath: String?
    let displayPriority: Int?

    var id: Int { providerID }

    enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case providerName = "provider_name"
        case logoPath = "logo_path"
        case displayPriority = "display_priority"
    }

    var selectionID: String {
        "tmdb:\(providerID):\(providerName)"
    }

    var logoURL: URL? {
        guard let logoPath, !logoPath.isEmpty else { return nil }
        return URL(string: "https://image.tmdb.org/t/p/w154\(logoPath)")
    }
}
