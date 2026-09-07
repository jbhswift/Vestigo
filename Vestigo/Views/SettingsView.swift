import SwiftUI
import Foundation

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject var model: VestigoModel
    @State private var selectedCategory: SettingsCategory = .content
    @AppStorage("Vestigo.devMode") private var devMode: Bool = false

    enum SettingsCategory: String, CaseIterable, Identifiable {
        case content
        case display
        case notifications
        case data
        case about
        case dev

        var id: String { rawValue }
        var title: String {
            switch self {
            case .display: return "Display"
            case .content: return "Content"
            case .notifications: return "Alerts"
            case .data: return "Data"
            case .about: return "About"
            case .dev: return "Dev"
            }
        }
    }

    var body: some View {
        BaseScreen(title: "Settings", filter: .constant(.both), settings: model.settings, contentTopPadding: 18) {
            VStack(alignment: .leading, spacing: 18) {
                settingsCategoryPills

                if selectedCategory == .display {
                    SettingsDisplaySection(model: model)
                }

                if selectedCategory == .content {
                    SettingsContentSection(model: model)
                }

                if selectedCategory == .data {
                    SettingsDataSection(model: model)
                }

                if selectedCategory == .about || selectedCategory == .dev {
                    SettingsAboutSection(model: model, selectedCategory: $selectedCategory)
                }
            }
        }
        .onChange(of: model.settings) { _, _ in
            model.saveSettings()
        }
    }

    private var visibleCategories: [SettingsCategory] {
        SettingsCategory.allCases.filter { $0 != .notifications && ($0 != .dev || devMode) }
    }

    private var settingsCategoryPills: some View {
        Picker("Settings category", selection: $selectedCategory) {
            ForEach(visibleCategories) { category in
                Text(category.title).tag(category)
            }
        }
        .pickerStyle(.segmented)
        .liquidGlass(cornerRadius: 18)
    }
}
