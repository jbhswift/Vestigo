import Foundation
import SwiftUI
#if canImport(AppIntents)
import AppIntents

// MARK: - Navigation intents

@available(iOS 16.0, *)
struct OpenPickForMeInVestigoIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Pick For Me in Vestigo"
    static var description = IntentDescription("Opens Vestigo directly to Pick For Me.", categoryName: "Navigation")
    static var openAppWhenRun: Bool = true

    static var parameterSummary: some ParameterSummary {
        Summary("Open Pick For Me in Vestigo")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .vestigoShortcut, object: "openPickForMe")
        return .result()
    }
}

#endif
