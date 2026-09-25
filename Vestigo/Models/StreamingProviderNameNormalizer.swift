import Foundation

enum StreamingProviderNameNormalizer {
    static func normalizedName(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "+", with: "plus")
            .filter { $0.isLetter || $0.isNumber }
    }

    static func normalizedWords(_ value: String) -> String {
        value
            .lowercased()
            .replacingOccurrences(of: "+", with: " plus ")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func dedupName(_ value: String) -> String {
        let words = normalizedWords(value)
        let stripped = offerQualifiers.reduce(words) { partial, qualifier in
            partial.replacingOccurrences(of: qualifier, with: " ")
        }
        return normalizedName(stripped)
    }

    static func offerQualifierScore(_ value: String) -> Int {
        let words = normalizedWords(value)
        return offerQualifiers.reduce(0) { score, qualifier in
            words.contains(qualifier) ? score + 1 : score
        }
    }

    static func isFreeProviderName(_ value: String) -> Bool {
        let words = normalizedWords(value)
        return offerQualifiers.contains { words.contains($0) }
    }

    static func isAddOnVariant(_ value: String) -> Bool {
        let words = normalizedWords(value)
        if addOnPhrases.contains(where: { words.contains($0) }) {
            return true
        }

        guard words.hasSuffix(" channel") else { return false }
        let base = words.dropLast(" channel".count).trimmingCharacters(in: .whitespacesAndNewlines)
        return base.split(separator: " ").count > 1
    }

    static func baseProviderName(from value: String) -> String {
        let words = normalizedWords(value)
        guard addOnPhrases.contains(where: { words.contains($0) }) else {
            return value
        }

        let stripped = addOnPhrases.reduce(value) { partial, phrase in
            partial.replacingOccurrences(of: phrase, with: " ", options: [.caseInsensitive])
        }
        return stripped
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let offerQualifiers = [
        "free with ads",
        "with ads",
        "ad supported",
        "ads",
        "free"
    ]

    private static let addOnPhrases = [
        "addon",
        "add on",
        "add-on",
        "premium channel",
        "amazon channel",
        "apple tv channel",
        "roku premium channel"
    ]
}
