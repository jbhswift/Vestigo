import Foundation

struct StreamingCatalogService {
    private let base = "https://mtttuyvpjyugudkevchj.supabase.co/functions/v1/vestigo-api"

    func services(forRegion country: String) async throws -> [RegionStreamingService] {
        var comps = URLComponents(string: base + "/streaming-catalog")!
        comps.queryItems = [URLQueryItem(name: "country", value: country)]
        guard let url = comps.url else { throw URLError(.badURL) }

        let request = URLRequest(url: url)
        let (data, response) = try await URLSession.shared.data(for: request)
        AnalyticsService.shared.track(.apiCallMade(service: "motn"))
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(StreamingCatalogResponse.self, from: data)
        return decoded.services
    }
}
