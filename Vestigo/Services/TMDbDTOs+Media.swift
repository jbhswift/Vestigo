import Foundation

struct TMDbPersonSearchResponse: Decodable {
    let results: [TMDbPersonSearchDTO]
}

struct TMDbPersonSearchDTO: Decodable {
    let id: Int
    let name: String
    let knownForDepartment: String?
    let profilePath: String?
    let popularity: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, popularity
        case knownForDepartment = "known_for_department"
        case profilePath = "profile_path"
    }
}

struct TMDbPersonCreditsResponse: Decodable {
    let cast: [TMDbMediaDTO]
    let crew: [TMDbMediaDTO]
}

struct TMDbPersonDetailResponse: Decodable {
    let id: Int
    let biography: String?
    let birthday: String?
    let deathday: String?
    let placeOfBirth: String?
    let knownForDepartment: String?
    let imdbID: String?

    enum CodingKeys: String, CodingKey {
        case id
        case biography
        case birthday
        case deathday
        case placeOfBirth = "place_of_birth"
        case knownForDepartment = "known_for_department"
        case imdbID = "imdb_id"
    }
}

struct TMDbMediaDTO: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let character: String?
    let job: String?
    let mediaType: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let voteCount: Int?
    let genreIDs: [Int]?
    let originalLanguage: String?
    let birthday: String?
    let deathday: String?
    let placeOfBirth: String?
    let knownForDepartment: String?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview, character, job
        case mediaType = "media_type"
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case genreIDs = "genre_ids"
        case originalLanguage = "original_language"
        case birthday
        case deathday
        case placeOfBirth = "place_of_birth"
        case knownForDepartment = "known_for_department"
    }
}

struct TMDbGenreDTO: Decodable {
    let id: Int
    let name: String?
}

struct TMDbStandaloneMediaDTO: Decodable {
    let id: Int
    let title: String?
    let name: String?
    let overview: String?
    let posterPath: String?
    let backdropPath: String?
    let releaseDate: String?
    let firstAirDate: String?
    let voteAverage: Double?
    let voteCount: Int?
    let genres: [TMDbGenreDTO]?
    let runtime: Int?
    let originalLanguage: String?

    enum CodingKeys: String, CodingKey {
        case id, title, name, overview, genres, runtime
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case originalLanguage = "original_language"
    }
}

struct TMDbProviderResponse: Decodable { let results: [String: TMDbProviderRegion] }
struct TMDbProviderRegion: Decodable { let flatrate: [TMDbProvider]?; let free: [TMDbProvider]?; let rent: [TMDbProvider]?; let buy: [TMDbProvider]? }
struct TMDbProvider: Decodable { let providerName: String; enum CodingKeys: String, CodingKey { case providerName = "provider_name" } }

struct WatchmodeShowResponse: Decodable {
    let title: String?
    let tmdbId: String?
    let releaseYear: Int?
    let firstAirYear: Int?
    let streamingOptions: [String: [WatchmodeOption]]?

    enum CodingKeys: String, CodingKey {
        case title
        case tmdbId
        case releaseYear
        case firstAirYear
        case streamingOptions
    }

    var matchYear: Int? {
        releaseYear ?? firstAirYear
    }

    var normalizedTitle: String {
        (title ?? "").normalizedForMatching
    }

    var usOptions: [StreamingOption] {
        let options = streamingOptions?["us"] ?? streamingOptions?["US"] ?? []
        return options.map { option in
            StreamingOption(
                serviceName: option.displayServiceName,
                type: option.displayTypeText,
                priceText: option.displayPriceText,
                qualityText: option.displayQualityText,
                openURL: option.displayOpenURL
            )
        }
    }
}
