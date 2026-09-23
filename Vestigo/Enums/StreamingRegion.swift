import Foundation

// MARK: - Streaming Region
//
// One case per country supported by the Streaming Availability API (Movie of the Night),
// which also determines what's offered in the Content settings country picker.

enum StreamingRegion: String, Codable, CaseIterable, Identifiable {
    case argentina = "AR"
    case australia = "AU"
    case austria = "AT"
    case azerbaijan = "AZ"
    case belgium = "BE"
    case bolivia = "BO"
    case brazil = "BR"
    case bulgaria = "BG"
    case canada = "CA"
    case chile = "CL"
    case colombia = "CO"
    case costaRica = "CR"
    case croatia = "HR"
    case cyprus = "CY"
    case czechRepublic = "CZ"
    case denmark = "DK"
    case ecuador = "EC"
    case elSalvador = "SV"
    case estonia = "EE"
    case finland = "FI"
    case france = "FR"
    case germany = "DE"
    case greece = "GR"
    case guatemala = "GT"
    case honduras = "HN"
    case hongKong = "HK"
    case hungary = "HU"
    case iceland = "IS"
    case india = "IN"
    case indonesia = "ID"
    case ireland = "IE"
    case israel = "IL"
    case italy = "IT"
    case japan = "JP"
    case lithuania = "LT"
    case malaysia = "MY"
    case mexico = "MX"
    case moldova = "MD"
    case netherlands = "NL"
    case newZealand = "NZ"
    case northMacedonia = "MK"
    case norway = "NO"
    case panama = "PA"
    case peru = "PE"
    case philippines = "PH"
    case poland = "PL"
    case portugal = "PT"
    case romania = "RO"
    case serbia = "RS"
    case singapore = "SG"
    case slovakia = "SK"
    case slovenia = "SI"
    case southAfrica = "ZA"
    case southKorea = "KR"
    case spain = "ES"
    case sweden = "SE"
    case switzerland = "CH"
    case thailand = "TH"
    case turkey = "TR"
    case ukraine = "UA"
    case unitedArabEmirates = "AE"
    case unitedKingdom = "GB"
    case unitedStates = "US"
    case venezuela = "VE"
    case vietnam = "VN"

    var id: String { rawValue }

    var displayName: String {
        Locale.current.localizedString(forRegionCode: rawValue) ?? rawValue
    }

    /// Regional-indicator-symbol flag emoji derived from the ISO 3166-1 alpha-2 code.
    var flagEmoji: String {
        let base: UInt32 = 127397
        var scalarView = String.UnicodeScalarView()
        for scalar in rawValue.unicodeScalars {
            if let flagScalar = Unicode.Scalar(base + scalar.value) {
                scalarView.append(flagScalar)
            }
        }
        return String(scalarView)
    }
}
