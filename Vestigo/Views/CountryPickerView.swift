import SwiftUI
import Foundation

struct CountryPickerView: View {
    @ObservedObject var model: VestigoModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var sortedRegions: [StreamingRegion] {
        StreamingRegion.allCases.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    private var filteredRegions: [StreamingRegion] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return sortedRegions }
        return sortedRegions.filter { $0.displayName.localizedCaseInsensitiveContains(trimmed) }
    }

    var body: some View {
        List {
            Picker("Region", selection: Binding(
                get: { model.settings.streamingRegion },
                set: { newValue in
                    model.settings.streamingRegion = newValue
                    model.saveSettings()
                    model.providerCache = [:]
                    dismiss()
                }
            )) {
                ForEach(filteredRegions) { region in
                    Text(region.displayName).tag(region)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .searchable(text: $searchText, prompt: "Search countries")
        .navigationTitle("Region")
        .navigationBarTitleDisplayMode(.inline)
    }
}
