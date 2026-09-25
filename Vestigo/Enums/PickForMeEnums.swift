import Foundation
import SwiftUI

// MARK: - PickForMe Option Protocol

protocol PickForMeOption: Identifiable, Hashable {
    var title: String { get }
    var subtitle: String? { get }
    var isAnyOption: Bool { get }
}

extension PickForMeOption {
    var subtitle: String? { nil }
    var isAnyOption: Bool { false }
}

extension MediaFilter: PickForMeOption {}

// MARK: - PickForMe Answers

struct PickForMeAnswers: Hashable, Codable {
    var mediaFormat: PickForMeMediaFormat?
    var archetypes: Set<PickForMeArchetype> = []
    var secondaryArchetypes: Set<PickForMeArchetype> = []
    var genrePreferences: Set<PickForMeGenrePreference> = []
    var fictionPreference: PickForMeFictionPreference?
    var sourceMaterial: PickForMeSourceMaterial?
    var runtimeRange: PickForMeRuntimeRange = .unconstrained
    var releaseAge: PickForMeReleaseAge?
    var contentRatings: Set<PickForMeContentRating> = []
    var minimumRating: PickForMeMinimumRating?
    var dealBreakers: Set<PickForMeDealBreaker> = []
    var myServicesOnly: Bool? = nil

    var answeredQuestionCount: Int {
        var count = 0
        if mediaFormat != nil { count += 1 }
        if !archetypes.isEmpty { count += 1 }
        if !secondaryArchetypes.isEmpty { count += 1 }
        if !genrePreferences.isEmpty { count += 1 }
        if fictionPreference != nil { count += 1 }
        if sourceMaterial != nil { count += 1 }
        if runtimeRange.hasConstraint { count += 1 }
        if releaseAge != nil { count += 1 }
        if !contentRatings.isEmpty { count += 1 }
        if minimumRating != nil { count += 1 }
        if !dealBreakers.isEmpty { count += 1 }
        return count
    }

    var meaningfulQuestionCount: Int {
        var count = 0
        if mediaFormat != nil { count += 1 }
        if !archetypes.isEmpty && !archetypes.contains(.surprise) { count += 1 }
        if !secondaryArchetypes.isEmpty && !secondaryArchetypes.contains(where: \.isAnyOption) { count += 1 }
        if !genrePreferences.isEmpty && !genrePreferences.contains(.noPreference) { count += 1 }
        if let fictionPreference, fictionPreference != .noPreference { count += 1 }
        if let sourceMaterial, sourceMaterial != .noPreference { count += 1 }
        if !isSeriesOnly && runtimeRange.hasConstraint { count += 1 }
        if let releaseAge, releaseAge != .noPreference { count += 1 }
        if !contentRatings.isEmpty && !contentRatings.contains(.any) { count += 1 }
        if let minimumRating, minimumRating != .any { count += 1 }
        if !dealBreakers.isEmpty && !dealBreakers.contains(.none) { count += 1 }
        return count
    }

    var effectiveMediaFilter: MediaFilter {
        mediaFormat?.mediaFilter ?? .both
    }

    var isSeriesOnly: Bool {
        mediaFormat == .series
    }

    var wantsDocumentary: Bool {
        archetypes.contains(.documentary) || secondaryArchetypes.contains(.documentary)
    }

    var wantsHumanTriumph: Bool {
        archetypes.contains(.humanTriumph) || secondaryArchetypes.contains(.humanTriumph)
    }

    var wantsStrictHistorical: Bool {
        archetypes.contains(.historical) ||
        secondaryArchetypes.contains(.historical)
    }

    var wantsHistoryFlavor: Bool {
        genrePreferences.contains(.history)
    }

    var wantsHistorical: Bool {
        wantsStrictHistorical || wantsHistoryFlavor
    }

    var wantsWar: Bool {
        archetypes.contains(.war) ||
        secondaryArchetypes.contains(.war) ||
        genrePreferences.contains(.war)
    }

    var wantsSpeculative: Bool {
        archetypes.contains(.thoughtfulSciFi) ||
        archetypes.contains(.mindBending) ||
        secondaryArchetypes.contains(.thoughtfulSciFi) ||
        secondaryArchetypes.contains(.mindBending) ||
        genrePreferences.contains(.sciFi) ||
        genrePreferences.contains(.fantasy) ||
        genrePreferences.contains(.space)
    }

    var prefersAdultLeaningMood: Bool {
        contentRatings.contains(.r) ||
        contentRatings.contains(.nc17) ||
        archetypes.contains(.horror) ||
        archetypes.contains(.thriller) ||
        archetypes.contains(.war) ||
        archetypes.contains(.mindBending) ||
        archetypes.contains(.smartProblems) ||
        secondaryArchetypes.contains(.horror) ||
        secondaryArchetypes.contains(.thriller) ||
        secondaryArchetypes.contains(.war) ||
        secondaryArchetypes.contains(.mindBending) ||
        secondaryArchetypes.contains(.smartProblems)
    }

    var summaryTags: [String] {
        var tags: [String] = []
        if let format = mediaFormat { tags.append(format.title) }
        let archetypeTags = archetypes.filter { $0 != .surprise && $0 != .noPreference }
            .map(\.title).sorted()
        tags.append(contentsOf: archetypeTags.prefix(3))
        if tags.count < 5 {
            let genreTags = genrePreferences.filter { $0 != .noPreference }
                .map(\.title).sorted()
            tags.append(contentsOf: genreTags.prefix(5 - tags.count))
        }
        return tags
    }

    var detailTags: [String] {
        var tags: [String] = []
        let secTags = secondaryArchetypes.filter { !$0.isAnyOption }.map(\.title).sorted()
        if !secTags.isEmpty { tags.append(contentsOf: secTags.prefix(2)) }
        if let fp = fictionPreference, fp != .noPreference { tags.append(fp.title) }
        if let sm = sourceMaterial, sm != .noPreference { tags.append(sm.title) }
        if let ra = releaseAge, ra != .noPreference { tags.append(ra.title) }
        if runtimeRange.hasConstraint { tags.append(runtimeRange.displayString) }
        if let mr = minimumRating, mr != .any { tags.append("Min \(mr.title)") }
        let db = dealBreakers.filter { !$0.isAnyOption }.map { "No \($0.title.lowercased())" }.sorted()
        if !db.isEmpty { tags.append(contentsOf: db.prefix(2)) }
        return tags
    }
}

// MARK: - PickForMe Steps

enum PickForMeStep: CaseIterable {
    case format, archetype, secondaryArchetypes, genrePreferences, fictionPreference, sourceMaterial, runtime, releaseAge, ageRating, minimumRating, dealBreakers, myServicesOnly

    static func steps(for answers: PickForMeAnswers) -> [PickForMeStep] {
        var steps: [PickForMeStep] = [
            .format,
            .archetype
        ]

        if !answers.archetypes.contains(.surprise) {
            steps.append(.secondaryArchetypes)
        }

        steps.append(contentsOf: [
            .genrePreferences,
            .fictionPreference
        ])

        steps.append(.sourceMaterial)

        if !answers.isSeriesOnly {
            steps.append(.runtime)
        }

        steps.append(contentsOf: [
            .releaseAge,
            .ageRating
        ])

        steps.append(contentsOf: [
            .minimumRating,
            .dealBreakers
        ])

        steps.append(.myServicesOnly)

        return steps
    }

    var title: String {
        switch self {
        case .format: return "What do you want to watch?"
        case .archetype: return "What are you in the mood for?"
        case .secondaryArchetypes: return "Anything else sound good?"
        case .genrePreferences: return "Any genre flavors you want?"
        case .fictionPreference: return "Fiction or non-fiction?"
        case .sourceMaterial: return "Adaptations?"
        case .runtime: return "How much time do you have?"
        case .releaseAge: return "How recent should it be?"
        case .ageRating: return "What content rating are you comfortable with?"
        case .minimumRating: return "How highly rated should it be?"
        case .dealBreakers: return "Any deal breakers?"
        case .myServicesOnly: return "Limit to your streaming services?"
        }
    }

    var subtitle: String? {
        switch self {
        case .format: return "Choose one."
        case .archetype: return "Choose one. Documentary is a strict filter; Historical means stories about historical events."
        case .secondaryArchetypes: return "Fewer is better — 1 or 2 gives the most focused results. Documentary is strict; Historical means stories about historical events."
        case .genrePreferences: return "Hard requirement — every result must fit. Each extra flavor you add reduces the pool significantly. 1 is ideal."
        case .fictionPreference: return "Can be very restrictive — no preference works best unless you specifically care. Based on a true story includes historical fiction and biopics. Non-fiction is documentary-only."
        case .sourceMaterial: return "Strict filter. Only set this if you specifically want a book or game adaptation."
        case .runtime: return "Runtime filters out movies outside the time window you choose."
        case .releaseAge: return "Release age is a strict filter, not a ranking boost."
        case .ageRating: return "This is a maximum rating filter when data is available. Missing data is penalized."
        case .minimumRating: return "Strong rating preference. Uses IMDb when available."
        case .dealBreakers: return "Strict filters. Choose none if nothing applies."
        case .myServicesOnly: return "Filters discover API calls with TMDb's with_watch_providers parameter. Library pool items (watchlist, recs) with nil providerCache pass through unchanged. Services without a mapped TMDb ID are excluded from the API filter but the post-filter still uses providerCache for them."
        }
    }

    var userSubtitle: String? {
        switch self {
        case .format: return "Choose one."
        case .archetype: return "Pick the vibe you're after. Choose one."
        case .secondaryArchetypes: return "Optional extras — 1 or 2 gives the most focused results."
        case .genrePreferences: return "Limits results to a specific genre or setting. 1 is ideal."
        case .fictionPreference: return "Leave on no preference unless you specifically care."
        case .sourceMaterial: return "Only set this if you want a book or game adaptation."
        case .runtime: return "Filter by how long you want to watch."
        case .releaseAge: return "Choose how old the film or show can be."
        case .ageRating: return "Pick the maximum content rating you're comfortable with."
        case .minimumRating: return "Choose a minimum quality bar."
        case .dealBreakers: return "Things you don't want to see. Choose none if nothing applies."
        case .myServicesOnly: return "Only suggest items available on your streaming services. Make sure your services are configured correctly — you can edit them below."
        }
    }
}

// MARK: - PickForMe Option Enums

enum PickForMeMediaFormat: String, CaseIterable, Codable, PickForMeOption {
    case movies, series, both

    init(_ filter: MediaFilter) {
        switch filter {
        case .movie:
            self = .movies
        case .tv:
            self = .series
        case .both:
            self = .both
        }
    }

    var id: String { rawValue }
    var title: String {
        switch self {
        case .movies: return "Movies"
        case .series: return "Series"
        case .both: return "Both"
        }
    }
    var isAnyOption: Bool { self == .both }
    var mediaFilter: MediaFilter {
        switch self {
        case .movies: return .movie
        case .series: return .tv
        case .both: return .both
        }
    }
}

enum PickForMeArchetype: String, CaseIterable, Codable, PickForMeOption {
    case feelGood, comedy, mystery, thriller, smartProblems, mission, heist, adventure, characterRelationships, humanTriumph, documentary, historical, war, epicSpectacle, mindBending, horror, thoughtfulSciFi, surprise, noPreference
    var id: String { rawValue }
    var title: String {
        switch self {
        case .feelGood: return "Feel-Good"
        case .comedy: return "Comedy"
        case .mystery: return "Mystery"
        case .thriller: return "Thriller"
        case .smartProblems: return "Smart people solving problems"
        case .mission: return "Mission"
        case .heist: return "Heist"
        case .adventure: return "Adventure"
        case .characterRelationships: return "Character and Relationships"
        case .humanTriumph: return "Human Triumph"
        case .documentary: return "Documentary"
        case .historical: return "Historical"
        case .war: return "War"
        case .epicSpectacle: return "Epic / Spectacle"
        case .mindBending: return "Mind-Bending"
        case .horror: return "Horror"
        case .thoughtfulSciFi: return "Thought-Provoking Sci-Fi"
        case .surprise: return "Surprise me"
        case .noPreference: return "No preference"
        }
    }
    var subtitle: String? {
        switch self {
        case .feelGood: return "Uplifting, optimistic, and heartwarming."
        case .comedy: return "Built primarily to make you laugh."
        case .mystery: return "Driven by uncovering hidden information."
        case .thriller: return "Tension, danger, suspense, or pursuit."
        case .smartProblems: return "Experts, teams, investigations, planning, or persistence."
        case .mission: return "A specific objective, operation, rescue, or survival mission."
        case .heist: return "Sophisticated capers, cons, and elaborate schemes."
        case .adventure: return "Exploration, discovery, and excitement."
        case .characterRelationships: return "Relationships, family dynamics, and personal growth."
        case .humanTriumph: return "Overcoming hurdles, resilience, achievement, or against-the-odds stories."
        case .documentary: return "Nonfiction, real subjects, and factual storytelling."
        case .historical: return "Fiction or nonfiction about a historical event."
        case .war: return "War, combat, military conflict, or wartime survival."
        case .epicSpectacle: return "Scale, visuals, action, and world-building."
        case .mindBending: return "Twists, puzzles, unusual structure, or reality-questioning stories."
        case .horror: return "Fear, dread, terror, or psychological discomfort."
        case .thoughtfulSciFi: return "Idea-driven science fiction, ethics, technology, or consciousness."
        case .surprise: return "Let the app lean on your history and strong ratings."
        case .noPreference: return nil
        }
    }
    var isAnyOption: Bool { self == .surprise || self == .noPreference }

    // TMDb keyword terms to look up for targeted discovery alongside genre-based discovery.
    // Only populated for archetypes where genre sorting alone leaves good films buried
    // (e.g. heist films at 7.2 rating sit far below the top of the Crime genre list).
    // Empty means genre-based discovery is already sufficient.
    var discoveryKeywords: [String] {
        switch self {
        case .heist:                  return ["heist", "caper"]
        case .mystery:                return ["murder mystery", "whodunit"]
        case .mission:                return ["espionage", "spy"]
        case .mindBending:            return ["unreliable narrator", "mind-bending"]
        case .thoughtfulSciFi:        return ["dystopia", "artificial intelligence"]
        case .humanTriumph:           return ["underdog"]
        case .adventure:              return ["treasure hunt"]
        case .characterRelationships: return ["coming of age"]
        // Genre-based discovery is sufficient for these
        case .feelGood, .comedy, .thriller, .smartProblems,
             .documentary, .historical, .war, .epicSpectacle, .horror,
             .surprise, .noPreference:
            return []
        }
    }

    var thematicDiscoveryPhrase: String? {
        switch self {
        case .feelGood: return "uplifting and heartwarming films that leave you feeling good"
        case .mystery: return "films built around uncovering secrets, whodunits, and clever detective stories"
        case .thriller: return "psychological thrillers with tension, suspense, and high stakes"
        case .smartProblems: return "films about brilliant minds solving impossible problems or pulling off complex plans"
        case .mission: return "films with high-stakes missions, operations, and survival objectives"
        case .heist: return "heist films, capers, and elaborate con schemes"
        case .characterRelationships: return "character-driven films exploring complex relationships and personal growth"
        case .humanTriumph: return "inspiring underdog stories of resilience and against-the-odds achievement"
        case .epicSpectacle: return "epic films with spectacular scale, grand visuals, and ambitious world-building"
        case .mindBending: return "mind-bending films with unreliable narrators, reality-questioning twists, and non-linear structure"
        case .thoughtfulSciFi: return "thought-provoking science fiction exploring big ideas, ethics, or consciousness"
        case .comedy, .adventure, .war, .horror, .documentary, .historical, .surprise, .noPreference: return nil
        }
    }

}

enum PickForMeGenrePreference: String, CaseIterable, Codable, PickForMeOption {
    case space, fantasy, sciFi, action, history, crime, war, romance, animation, family, horror, comedy, noPreference
    var id: String { rawValue }
    var title: String {
        switch self {
        case .space: return "Space"
        case .fantasy: return "Fantasy"
        case .sciFi: return "Sci-Fi"
        case .action: return "Action"
        case .history: return "History"
        case .crime: return "Crime"
        case .war: return "War"
        case .romance: return "Romance"
        case .animation: return "Animation"
        case .family: return "Family"
        case .horror: return "Horror"
        case .comedy: return "Comedy"
        case .noPreference: return "No preference"
        }
    }
    var isAnyOption: Bool { self == .noPreference }

}

enum PickForMeFictionPreference: String, CaseIterable, Codable, PickForMeOption {
    case fiction, basedOnTrueStory, nonFiction, noPreference
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fiction: return "Completely fictional"
        case .basedOnTrueStory: return "Based on a true story"
        case .nonFiction: return "Non-fiction / Documentary only"
        case .noPreference: return "No preference"
        }
    }
    var subtitle: String? {
        switch self {
        case .fiction: return "Made-up stories only — avoids documentaries and true-event content."
        case .basedOnTrueStory: return "Includes historical fiction, biopics, and documentaries."
        case .nonFiction: return "Strict filter — documentaries and non-fiction only."
        case .noPreference: return nil
        }
    }
    var userSubtitle: String? {
        switch self {
        case .fiction: return "Made-up stories only."
        case .basedOnTrueStory: return "Historical fiction, biopics, and documentaries."
        case .nonFiction: return "Documentaries and non-fiction only."
        case .noPreference: return nil
        }
    }
    var isAnyOption: Bool { self == .noPreference }
}

enum PickForMeSourceMaterial: String, CaseIterable, Codable, PickForMeOption {
    case book, game, noPreference
    var id: String { rawValue }
    var title: String {
        switch self {
        case .book: return "Based on a book"
        case .game: return "Based on a game"
        case .noPreference: return "No preference"
        }
    }
    var isAnyOption: Bool { self == .noPreference }
    var keywordIDs: [Int] {
        switch self {
        case .book: return [818]
        case .game: return [41645]
        case .noPreference: return []
        }
    }
}

struct PickForMeRuntimeRange: Hashable, Codable {
    var minMinutes: Int  // 0 = no minimum
    var maxMinutes: Int  // 0 = no maximum

    static let unconstrained = PickForMeRuntimeRange(minMinutes: 0, maxMinutes: 0)
    static let steps = [0, 30, 60, 90, 120, 150, 180, 210, 240]

    var hasConstraint: Bool { minMinutes > 0 || maxMinutes > 0 }

    func contains(_ minutes: Int) -> Bool {
        if minMinutes > 0 && minutes < minMinutes { return false }
        if maxMinutes > 0 && minutes > maxMinutes { return false }
        return true
    }

    var displayString: String {
        let minStr = minMinutes > 0 ? Self.formatMinutes(minMinutes) : nil
        let maxStr = maxMinutes > 0 ? Self.formatMinutes(maxMinutes) : nil
        switch (minStr, maxStr) {
        case (nil, nil): return "Any length"
        case (let min?, nil): return "\(min) or more"
        case (nil, let max?): return "Up to \(max)"
        case (let min?, let max?): return "\(min) – \(max)"
        }
    }

    static func formatMinutes(_ m: Int) -> String {
        guard m > 0 else { return "Any" }
        let h = m / 60, mins = m % 60
        if h == 0 { return "\(mins)m" }
        return mins == 0 ? "\(h)h" : "\(h)h \(mins)m"
    }
}
