import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Text Extensions

extension Text {
    func sectionTitle() -> some View {
        self.font(.system(size: 20, weight: .black, design: .rounded))
    }
}

// MARK: - Color Helpers

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r = Double((int >> 16) & 0xFF) / 255
        let g = Double((int >> 8)  & 0xFF) / 255
        let b = Double(int & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - String Extensions

extension String {
    var isUnknownPlaceholder: Bool {
        let normalized = trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "unknown" || normalized == "unknown price" || normalized == "price unknown" || normalized == "unknown quality" || normalized == "quality unknown" || normalized == "n/a" || normalized == "na" || normalized == "none"
    }

    var normalizedForMatching: String {
        lowercased()
            .replacingOccurrences(of: "&", with: "and")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
