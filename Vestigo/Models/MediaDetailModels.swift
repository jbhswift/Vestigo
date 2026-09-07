import Foundation

struct MediaDetail: Hashable {
    let director: PersonSummary?
    let creator: PersonSummary?
    let cast: [PersonSummary]
    let castAndKeyCrew: [PersonSummary]
    let seasons: [SeasonInfo]
    let similar: [MediaItem]
    let firstAirDate: String?
    let lastAirDate: String?
    let status: String?
    let runtime: Int?
    let ageRating: String?
    let tmdbCollectionID: Int?
    let keywordIDs: [Int]
    let keywordNames: [String]
    let networkNames: [String]
    let trailers: [TrailerVideo]
    let imdbID: String?
    let tmdbProviders: [StreamingOption]
    let sameFranchiseKeys: Set<MediaKey>
    let strongAPISimilarityKeys: Set<MediaKey>
    let mediumAPISimilarityKeys: Set<MediaKey>
    let sharedContributorKeys: Set<MediaKey>

    init(response: TMDbDetailResponse, fallback: MediaItem, regionCode: String = "US") {
        let crewList: [PersonDTO] = response.credits?.crew ?? []
        let castList: [PersonDTO] = response.credits?.cast ?? []
        tmdbCollectionID = response.belongsToCollection?.id
        firstAirDate = response.firstAirDate
        lastAirDate = response.lastAirDate
        status = response.status
        runtime = response.runtime
        ageRating = response.usAgeRating
        let allKeywords: [TMDbKeyword] = response.keywords?.keywords ?? response.keywords?.results ?? []
        keywordIDs = allKeywords.map(\.id)
        keywordNames = allKeywords.map(\.name)
        networkNames = (response.networks ?? []).map(\.name)
        trailers = TrailerVideo.ranked(from: response.videos?.results ?? [])
        imdbID = response.externalIDs?.imdbID
        tmdbProviders = response.watchProviders?.streamingOptions(for: regionCode) ?? []
        sameFranchiseKeys = []
        sharedContributorKeys = []

        let directorDTO = crewList.first { dto in
            dto.job == "Director"
        }
        director = directorDTO.map { dto in
            PersonSummary(dto, fallbackRole: "Director")
        }

        let creatorDTO = response.createdBy?.first
        creator = creatorDTO.map { dto in
            PersonSummary(dto, fallbackRole: "Creator")
        }

        let mappedCast: [PersonSummary] = castList.map { dto in
            PersonSummary(dto)
        }
        cast = mappedCast

        let keyCrewJobs: Set<String> = [
            "Director",
            "Creator",
            "Executive Producer",
            "Producer",
            "Writer",
            "Screenplay",
            "Story"
        ]

        let filteredCrewDTOs: [PersonDTO] = crewList.filter { dto in
            guard let job = dto.job else { return false }
            return keyCrewJobs.contains(job)
        }

        let mappedKeyCrew: [PersonSummary] = filteredCrewDTOs.map { dto in
            PersonSummary(dto)
        }

        let castIDs = Set(mappedCast.map { person in
            person.id
        })
        let uniqueKeyCrew = mappedKeyCrew.uniquedPeople(excluding: castIDs)
        castAndKeyCrew = mappedCast + uniqueKeyCrew

        let rawSeasons: [SeasonDTO] = response.seasons ?? []
        let normalSeasons = rawSeasons.filter { season in
            (season.seasonNumber ?? 0) > 0
        }
        seasons = normalSeasons.map { season in
            let number = season.seasonNumber ?? 1
            let name = season.name ?? "Season \(number)"
            let airDate = season.airDate
            let episodes: [EpisodeInfo] = (season.episodes ?? []).map { episode in
                let episodeNumber = episode.episodeNumber ?? 1
                return EpisodeInfo(
                    number: episodeNumber,
                    title: episode.name ?? "Episode \(episodeNumber)",
                    airDate: episode.airDate,
                    runtime: episode.runtime,
                    stillPath: episode.stillPath
                )
            }
            let count = season.episodeCount ?? episodes.count
            return SeasonInfo(number: number, name: name, airDate: airDate, episodeCount: count, episodes: episodes)
        }

        let recommendationItems: [MediaItem] = (response.recommendations?.results ?? []).map { MediaItem($0) }
        let similarItems: [MediaItem] = (response.similar?.results ?? []).map { MediaItem($0) }
        let strongAPISimilarityKeys = Set(recommendationItems.map(\.key))
        let mediumAPISimilarityKeys = Set(similarItems.map(\.key)).subtracting(strongAPISimilarityKeys)
        self.strongAPISimilarityKeys = strongAPISimilarityKeys
        self.mediumAPISimilarityKeys = mediumAPISimilarityKeys
        let mappedSimilar: [MediaItem] = recommendationItems + similarItems
        similar = Self.rankedSimilarItems(
            mappedSimilar.uniqued().filter { $0.shouldShowInDiscovery && !$0.isUpcoming && $0.key != fallback.key },
            source: fallback,
            strongAPISimilarityKeys: strongAPISimilarityKeys,
            mediumAPISimilarityKeys: mediumAPISimilarityKeys
        )
    }

    func addingSimilarCandidates(
        _ candidates: [MediaItem],
        source: MediaItem,
        sameFranchiseKeys: Set<MediaKey> = [],
        strongAPISimilarityKeys: Set<MediaKey> = [],
        mediumAPISimilarityKeys: Set<MediaKey> = [],
        sharedContributorKeys: Set<MediaKey> = [],
        externalRatings: [MediaKey: ExternalRatings] = [:]
    ) -> MediaDetail {
        let mergedSameFranchiseKeys = self.sameFranchiseKeys.union(sameFranchiseKeys)
        let mergedStrongAPISimilarityKeys = self.strongAPISimilarityKeys.union(strongAPISimilarityKeys)
        let mergedMediumAPISimilarityKeys = self.mediumAPISimilarityKeys.union(mediumAPISimilarityKeys)
        let mergedSharedContributorKeys = self.sharedContributorKeys.union(sharedContributorKeys)

        return MediaDetail(
            director: director,
            creator: creator,
            cast: cast,
            castAndKeyCrew: castAndKeyCrew,
            seasons: seasons,
            similar: Self.rankedSimilarItems(
                (similar + candidates).uniqued().filter { $0.shouldShowInDiscovery && !$0.isUpcoming && $0.key != source.key },
                source: source,
                sameFranchiseKeys: mergedSameFranchiseKeys,
                strongAPISimilarityKeys: mergedStrongAPISimilarityKeys,
                mediumAPISimilarityKeys: mergedMediumAPISimilarityKeys,
                sharedContributorKeys: mergedSharedContributorKeys,
                externalRatings: externalRatings
            ),
            firstAirDate: firstAirDate,
            lastAirDate: lastAirDate,
            status: status,
            runtime: runtime,
            ageRating: ageRating,
            tmdbCollectionID: tmdbCollectionID,
            keywordIDs: keywordIDs,
            keywordNames: keywordNames,
            networkNames: networkNames,
            trailers: trailers,
            imdbID: imdbID,
            tmdbProviders: tmdbProviders,
            sameFranchiseKeys: mergedSameFranchiseKeys,
            strongAPISimilarityKeys: mergedStrongAPISimilarityKeys,
            mediumAPISimilarityKeys: mergedMediumAPISimilarityKeys,
            sharedContributorKeys: mergedSharedContributorKeys
        )
    }

    var primaryTrailer: TrailerVideo? {
        trailers.first
    }

    func withTrailers(_ newTrailers: [TrailerVideo]) -> MediaDetail {
        MediaDetail(
            director: director, creator: creator, cast: cast, castAndKeyCrew: castAndKeyCrew,
            seasons: seasons, similar: similar, firstAirDate: firstAirDate, lastAirDate: lastAirDate,
            status: status, runtime: runtime, ageRating: ageRating, tmdbCollectionID: tmdbCollectionID,
            keywordIDs: keywordIDs, keywordNames: keywordNames, networkNames: networkNames,
            trailers: newTrailers, imdbID: imdbID, tmdbProviders: tmdbProviders,
            sameFranchiseKeys: sameFranchiseKeys, strongAPISimilarityKeys: strongAPISimilarityKeys,
            mediumAPISimilarityKeys: mediumAPISimilarityKeys, sharedContributorKeys: sharedContributorKeys
        )
    }

    private init(director: PersonSummary?, creator: PersonSummary?, cast: [PersonSummary], castAndKeyCrew: [PersonSummary], seasons: [SeasonInfo], similar: [MediaItem], firstAirDate: String?, lastAirDate: String?, status: String?, runtime: Int?, ageRating: String?, tmdbCollectionID: Int?, keywordIDs: [Int], keywordNames: [String], networkNames: [String], trailers: [TrailerVideo], imdbID: String?, tmdbProviders: [StreamingOption], sameFranchiseKeys: Set<MediaKey>, strongAPISimilarityKeys: Set<MediaKey>, mediumAPISimilarityKeys: Set<MediaKey>, sharedContributorKeys: Set<MediaKey>) {
        self.director = director
        self.creator = creator
        self.cast = cast
        self.castAndKeyCrew = castAndKeyCrew
        self.seasons = seasons
        self.similar = similar
        self.firstAirDate = firstAirDate
        self.lastAirDate = lastAirDate
        self.status = status
        self.runtime = runtime
        self.ageRating = ageRating
        self.tmdbCollectionID = tmdbCollectionID
        self.keywordIDs = keywordIDs
        self.keywordNames = keywordNames
        self.networkNames = networkNames
        self.trailers = trailers
        self.imdbID = imdbID
        self.tmdbProviders = tmdbProviders
        self.sameFranchiseKeys = sameFranchiseKeys
        self.strongAPISimilarityKeys = strongAPISimilarityKeys
        self.mediumAPISimilarityKeys = mediumAPISimilarityKeys
        self.sharedContributorKeys = sharedContributorKeys
    }

    var yearRangeText: String {
        guard let startYear = firstAirDate?.prefix(4), !startYear.isEmpty else {
            return "Unknown"
        }

        let normalizedStatus = status?.lowercased() ?? ""

        if normalizedStatus.contains("returning") ||
            normalizedStatus.contains("planned") ||
            normalizedStatus.contains("production") {
            return "\(startYear)–present"
        }

        if let endYear = lastAirDate?.prefix(4), !endYear.isEmpty, endYear != startYear {
            return "\(startYear)–\(endYear)"
        }

        return String(startYear)
    }
}
