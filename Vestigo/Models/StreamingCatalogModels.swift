import Foundation

struct RegionStreamingService: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let homePage: String?
    let themeColorHex: String?
    let logoURL: String?
    let isFree: Bool
}

struct StreamingCatalogResponse: Decodable {
    let ok: Bool
    let country: String?
    let services: [RegionStreamingService]
}
