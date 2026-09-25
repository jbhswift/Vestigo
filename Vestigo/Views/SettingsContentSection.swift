import SwiftUI
import Foundation

struct SettingsContentSection: View {
    @ObservedObject var model: VestigoModel

    var body: some View {
        Text("Content")
            .sectionTitle()
            .padding(.top, 6)

        StreamingAvailabilitySettingsSection(model: model)

        VStack(alignment: .leading, spacing: 10) {

            VStack(alignment: .leading, spacing: 10) {
                Text("Ratings source")
                    .font(.headline.bold())
                Picker("Ratings source", selection: $model.settings.preferredRatingSource) {
                    Text("TMDb").tag(RatingSource.tmdb)
                    Text("IMDb").tag(RatingSource.imdb)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .liquidGlass(cornerRadius: 18)
                .onChange(of: model.settings.preferredRatingSource) { _, newValue in
                    if newValue == .imdb {
                        model.refreshVisibleExternalRatings()
                    }
                }
                Text("IMDb scores from OMDb are used for rating displays, filters, and sorts where available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Prioritise English", isOn: $model.settings.prioritiseEnglish)
                    .font(.headline.bold())
                    .tint(model.settings.accentColor)

                Text("When this is on, English-language titles are shown first when otherwise similar results are available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()
            .onChange(of: model.settings.prioritiseEnglish) { _, _ in
                model.searchResults = model.preparedResults(model.searchResults)
                Task { await model.loadHome() }
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Hide adult/explicit results", isOn: $model.settings.hideAdultResults)
                    .font(.headline.bold())
                    .tint(model.settings.accentColor)

                Text("When this is on, searches and browsed results avoid adult-marked TMDb entries where the API supports that filtering. When it is off, TMDb may include adult-marked results.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()
            .onChange(of: model.settings.hideAdultResults) { _, _ in
                model.updateSearch()
                Task { await model.loadHome() }
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Hide anime", isOn: $model.settings.hideAnimeResults)
                    .font(.headline.bold())
                    .tint(model.settings.accentColor)

                Text("When this is on, anime and likely anime-related results are filtered out where possible. This may also hide anime-adjacent titles that are not considered actual anime.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()
            .onChange(of: model.settings.hideAnimeResults) { _, _ in
                model.searchResults = model.preparedResults(model.searchResults)
                Task { await model.loadHome() }
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Reduce child-focused results", isOn: $model.settings.hideLowestAgeRatings)
                    .font(.headline.bold())
                    .tint(model.settings.accentColor)

                Text("When this is on, Vestigo hides known youngest-audience ratings where certification data is available, and downweights likely child-focused animation in recommendations.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()
            .onChange(of: model.settings.hideLowestAgeRatings) { _, _ in
                model.searchResults = model.preparedResults(model.searchResults)
                model.updateSearch()
                Task { await model.loadHome() }
            }

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Hide from Home", isOn: $model.settings.hideWatchedFromHome)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .tint(model.settings.accentColor)
                        .padding(.trailing, 6)

                    Toggle("Hide from Search", isOn: $model.settings.hideWatchedFromSearch)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .tint(model.settings.accentColor)
                        .padding(.trailing, 6)
                }
                .padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hide watched results")
                        .font(.headline.bold())
                        .foregroundStyle(.primary)

                    Text("Choose where items you have already marked as watched should be hidden. Watchlist and Collections still show their saved contents.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(.primary)
            .tint(model.settings.accentColor)
            .settingBubble()
            .onChange(of: model.settings.hideWatchedFromHome) { _, _ in
                Task { await model.loadHome() }
            }
            .onChange(of: model.settings.hideWatchedFromSearch) { _, _ in
                model.searchResults = model.preparedResults(model.searchResults, hideWatched: model.settings.hideWatchedFromSearch)

                Task {
                    for route in model.searchPath {
                        if case .genre(let genreRoute) = route {
                            await model.loadGenre(genreRoute.genre)
                        }
                    }
                }
            }

            ShortFilmsSettingsGroup(model: model)
            ExtrasAndPromosSettingsGroup(model: model)

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("Search", isOn: $model.settings.hideUpcomingFromSearch)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .tint(model.settings.accentColor)
                        .padding(.trailing, 6)

                    Toggle("Collection and franchise recommendations", isOn: $model.settings.hideUpcomingFromCollectionRecommendations)
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                        .tint(model.settings.accentColor)
                        .padding(.trailing, 6)
                }
                .padding(.top, 8)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hide upcoming releases")
                        .font(.headline.bold())
                        .foregroundStyle(.primary)

                    Text("Choose where unreleased titles should be hidden. Home does not have a toggle because Upcoming releases is its own carousel.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(.primary)
            .tint(model.settings.accentColor)
            .settingBubble()
            .onChange(of: model.settings.hideUpcomingFromSearch) { _, _ in
                model.updateSearch()

                Task {
                    for route in model.searchPath {
                        if case .genre(let genreRoute) = route {
                            await model.loadGenre(genreRoute.genre)
                        }
                    }
                }
            }
            .onChange(of: model.settings.hideUpcomingFromRecommended) { _, _ in
                Task { await model.loadSmartRecommendations() }
            }
            .onChange(of: model.settings.hideUpcomingFromCollectionRecommendations) { _, _ in
                Task {
                    for collection in model.library.collections {
                        await model.loadCollectionRecommendations(for: collection.id)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Remove items from watchlist", isOn: $model.settings.removeItemsFromWatchlist)
                    .font(.headline.bold())
                    .tint(model.settings.accentColor)

                Text("When this is on, marking a saved item as watched removes it from Watchlist. When it is off, watched saved items stay in Watchlist under the Watched section.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Prompt to rate after marking watched", isOn: $model.settings.promptToRateAfterMarkingWatched)
                    .font(.headline.bold())
                    .tint(model.settings.accentColor)

                Text("When this is on, marking a movie or series as watched opens a rating prompt right where you are.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Automatically track watch date", isOn: $model.settings.autoTrackWatchDate)
                    .font(.headline.bold())
                    .tint(model.settings.accentColor)

                Text("When off, watch dates are set manually. When on, the date is recorded automatically the moment you mark something as watched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Show upcoming releases", isOn: $model.settings.showUpcomingReleases)
                    .font(.headline.bold())
                    .tint(model.settings.accentColor)

                Text("When this is on, Home shows unreleased movies and series in the Upcoming section.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()
            .onChange(of: model.settings.showUpcomingReleases) { _, _ in
                Task { await model.loadHome() }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Default Home Filter")
                    .font(.headline.bold())

                FilterPills(
                    filter: Binding(
                        get: { model.settings.defaultHomeFilter },
                        set: { newValue in
                            model.settings.defaultHomeFilter = newValue
                            model.mediaFilter = newValue
                            Task { await model.loadHome() }
                        }
                    ),
                    options: [.movie, .tv, .both]
                ) {
                    model.mediaFilter = model.settings.defaultHomeFilter
                    Task { await model.loadHome() }
                }

                Text("Choose whether Home opens to movies, series, or both.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()

            VStack(alignment: .leading, spacing: 8) {
                Text("Default Search Type")
                    .font(.headline.bold())

                SearchFilterPills(
                    filter: Binding(
                        get: { model.settings.defaultSearchFilter },
                        set: { newValue in
                            model.settings.defaultSearchFilter = newValue
                            model.searchFilter = newValue
                            model.updateSearch()
                        }
                    )
                ) {
                    model.searchFilter = model.settings.defaultSearchFilter
                    model.updateSearch()
                }

                Text("Choose which type Search opens with by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()

            VStack(alignment: .leading, spacing: 8) {
                Text("Default Category Sort")
                    .font(.headline.bold())

                GenreSortPicker(
                    sort: Binding(
                        get: { model.settings.defaultCategorySort },
                        set: { newValue in
                            model.settings.defaultCategorySort = newValue
                        }
                    )
                ) { }

                Text("Choose whether category pages open sorted by IMDb rating or release date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .settingBubble()

        }
    }
}

// MARK: - Private helper (only used by SettingsContentSection)

private struct StreamingAvailabilitySettingsSection: View {
    @ObservedObject var model: VestigoModel
    @State private var showSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Streaming Services")
                        .font(.headline.bold())
                    let count = model.settings.subscribedServiceNames.count
                    Text(count == 0 ? "None selected — showing all services" : "\(count) service\(count == 1 ? "" : "s") selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Manage") { showSheet = true }
                    .font(.subheadline)
                    .foregroundStyle(model.settings.accentColor)
            }

            Divider()
                .overlay(.white.opacity(0.08))

            HStack {
                Text("Region")
                    .font(.headline.bold())
                Spacer()
                Picker("Region", selection: Binding(
                    get: { model.settings.streamingRegion },
                    set: { newValue in
                        model.settings.streamingRegion = newValue
                        model.saveSettings()
                        model.providerCache = [:]
                        Task { await model.loadStreamingServiceCatalog() }
                    }
                )) {
                    ForEach(StreamingRegion.allCases.sorted(by: { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending })) { region in
                        Text(region.displayName).tag(region)
                    }
                }
                .pickerStyle(.menu)
                .foregroundStyle(model.settings.accentColor)
            }
        }
        .settingBubble()
        .sheet(isPresented: $showSheet) {
            StreamingServicesSetupSheet(model: model, isOnboarding: false)
        }
    }
}
