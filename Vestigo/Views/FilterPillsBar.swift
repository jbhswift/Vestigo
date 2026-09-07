import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - SearchBubble

struct SearchBubble: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
            TextField("Search movies, series, people...", text: $text)
                .textFieldStyle(.plain)
                .focused(isFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(false)
                .submitLabel(.search)
                .onSubmit {
                    onSubmit()
                }
        }
        .padding(.horizontal, 14)
        .frame(height: 52)
        .liquidGlass(cornerRadius: 24)
    }
}

// MARK: - FilterPills

struct FilterPills: View {
    @Binding var filter: MediaFilter
    let options: [MediaFilter]
    let onChange: () -> Void

    var body: some View {
        Picker("Filter", selection: $filter) {
            ForEach(options) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .liquidGlass(cornerRadius: 18)
        .onChange(of: filter) { _, _ in
            onChange()
        }
    }
}

// MARK: - SortPicker

struct SortPicker: View {
    @Binding var sort: SortOption
    let includeMyRating: Bool
    let ratingSource: RatingSource

    var body: some View {
        Picker("Sort", selection: $sort) {
            Text("Released").tag(SortOption.releaseDate)

            if includeMyRating {
                Text("My rating").tag(SortOption.myRating)
            }

            Text(ratingSource.title).tag(SortOption.tmdbRating)
        }
        .pickerStyle(.segmented)
        .liquidGlass(cornerRadius: 18)
    }
}

// MARK: - SortDirectionButton

struct SortDirectionButton: View {
    @Binding var direction: SortDirection

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                direction.toggle()
            }
        } label: {
            Image(systemName: direction.iconName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
                .frame(width: 42, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .liquidGlass(cornerRadius: 18)
        .accessibilityLabel(direction.accessibilityLabel)
    }
}

// MARK: - SortRow

struct SortRow<Picker: View>: View {
    @Binding var direction: SortDirection
    @ViewBuilder let picker: Picker

    var body: some View {
        HStack(spacing: 8) {
            picker
                .frame(maxWidth: .infinity)

            SortDirectionButton(direction: $direction)
        }
    }
}

// MARK: - PersonKnownForSortPicker

struct PersonKnownForSortPicker: View {
    @Binding var sort: PersonKnownForSort

    var body: some View {
        Picker("Sort", selection: $sort) {
            ForEach(PersonKnownForSort.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .liquidGlass(cornerRadius: 18)
    }
}
