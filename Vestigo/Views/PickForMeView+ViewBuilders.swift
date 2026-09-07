import SwiftUI
import Foundation

// MARK: - PickForMeView view-builder helpers

extension PickForMeView {

    // MARK: Top-level content routing

    @ViewBuilder var mainContent: some View {
        if isReviewingAnswers && !isEditingAnswerFromReview {
            answerReviewContent
        } else if results.isEmpty || isEditingAnswerFromReview {
            questionContent
        } else {
            PickForMeResultsView(
                model: model,
                results: results,
                resultIndex: resultIndex,
                fallbackText: fallbackText,
                onShowPrevious: showPreviousResult,
                onShowNext: showNextResult,
                onEditAnswers: editAnswers,
                onToggleNotInterested: toggleNotInterestedForCurrentResult,
                onToggleNeverShowAgain: toggleNeverShowAgainForCurrentResult
            )
            .offset(x: resultDragOffset)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.8), value: resultDragOffset)
        }
    }

    // MARK: Header

    var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Pick for me")
                    .font(.largeTitle.bold())
                Spacer()
                Button {
                    showingInfoSheet = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .sheet(isPresented: $showingInfoSheet) {
                    PickForMeInfoSheet()
                }
            }

            if isReviewingAnswers && !isEditingAnswerFromReview {
                Text("Review your answers, edit a specific question, or regenerate.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if results.isEmpty || isEditingAnswerFromReview {
                Text("Answer each question. Use no preference when you do not care.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("Recommendation \(resultIndex + 1) of \(results.count)")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Question flow

    var questionContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            progressView

            Text(currentStep.title)
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            if let subtitle = devMode ? currentStep.subtitle : currentStep.userSubtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 8) {
                    answerOptions
                }
            } else {
                answerOptions
            }

            if let errorText {
                StatusBubble(title: "Choose an answer", text: errorText)
            }

            HStack(spacing: 10) {
                Button {
                    goBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                        .font(.headline.bold())
                        .frame(width: 104)
                        .frame(height: 52)
                        .contentShape(Rectangle())
                        .liquidGlass(cornerRadius: 26)
                }
                .buttonStyle(.plain)
                .disabled(isLoading || step == 0)
                .opacity(step == 0 ? 0.45 : 1)

                Button {
                    advance()
                } label: {
                    Label(nextButtonTitle, systemImage: nextButtonIcon)
                    .font(.headline.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                    .liquidGlass(cornerRadius: 26)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .opacity(isLoading ? 0.55 : 1)
            }

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Finding a good fit...")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                }
            }

            if step == 0 {
                recentSearchesSection
            }
        }
    }

    @ViewBuilder var recentSearchesSection: some View {
        let recents = model.settings.pickForMeRecentSearches
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Recent searches")
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    ForEach(recents) { search in
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                answers = search.answers
                                isReviewingAnswers = true
                            }
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(recentSearchDateLabel(search.date))
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                    Text(search.answers.summaryTags.isEmpty ? "No preferences set" : search.answers.summaryTags.joined(separator: ", "))
                                        .font(.caption.bold())
                                        .foregroundStyle(.primary)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if !search.answers.detailTags.isEmpty {
                                        Text(search.answers.detailTags.joined(separator: " · "))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                Image(systemName: "arrow.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .liquidGlass(cornerRadius: 16)
                        }
                        .buttonStyle(.plain)
                        .swipeToDelete(cornerRadius: 16) { model.removePickForMeRecentSearch(search) }
                    }
                }
            }
        }
    }

    func recentSearchDateLabel(_ date: Date) -> String {
        let cal = Calendar.current
        let time = date.formatted(.dateTime.hour().minute())
        if cal.isDateInToday(date) { return "Today at \(time)" }
        if cal.isDateInYesterday(date) { return "Yesterday at \(time)" }
        return date.formatted(.dateTime.month(.abbreviated).day()) + " at \(time)"
    }

    var progressView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(step + 1) / \(steps.count)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.12))
                    Capsule()
                        .fill(model.settings.accentColor)
                        .frame(width: proxy.size.width * CGFloat(step + 1) / CGFloat(steps.count))
                }
            }
            .frame(height: 7)
        }
    }

    var nextButtonTitle: String {
        if isEditingAnswerFromReview {
            return "Done"
        }
        return step == steps.count - 1 ? "Check Results" : "Next"
    }

    var nextButtonIcon: String {
        if isEditingAnswerFromReview {
            return "checkmark"
        }
        return step == steps.count - 1 ? "sparkles" : "chevron.right"
    }

    // MARK: Answer options routing

    @ViewBuilder var answerOptions: some View {
        switch currentStep {
        case .format:
            mediaFormatChoiceList(selection: $answers.mediaFormat)
        case .archetype:
            primaryArchetypeChoiceList(selection: $answers.archetypes)
        case .secondaryArchetypes:
            multiChoiceList(secondaryArchetypeOptions, selection: $answers.secondaryArchetypes)
        case .genrePreferences:
            multiChoiceList(PickForMeGenrePreference.allCases, selection: $answers.genrePreferences)
        case .fictionPreference:
            fictionChoiceList(selection: $answers.fictionPreference)
        case .sourceMaterial:
            singleChoiceList(PickForMeSourceMaterial.allCases, selection: $answers.sourceMaterial)
        case .runtime:
            RuntimeRangeSlider(range: $answers.runtimeRange, accentColor: model.settings.accentColor)
        case .releaseAge:
            singleChoiceList(PickForMeReleaseAge.allCases, selection: $answers.releaseAge)
        case .ageRating:
            multiChoiceList(PickForMeContentRating.allCases, selection: $answers.contentRatings)
        case .minimumRating:
            singleChoiceList(PickForMeMinimumRating.allCases, selection: $answers.minimumRating)
        case .dealBreakers:
            multiChoiceList(dealBreakerOptions, selection: $answers.dealBreakers)
        case .myServicesOnly:
            myServicesOnlyOptions
        }
    }

    // MARK: Review content

    var reviewRows: some View {
        VStack(spacing: 10) {
            ForEach(Array(steps.enumerated()), id: \.element) { index, reviewStep in
                Button {
                    step = index
                    isEditingAnswerFromReview = true
                    errorText = nil
                } label: {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(reviewStep.title)
                                .font(.subheadline.bold())
                                .foregroundStyle(.primary)
                                .lineLimit(2)

                            Text(answerSummary(for: reviewStep))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                    .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                    .liquidGlass(cornerRadius: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    var answerReviewContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                startOver()
            } label: {
                Label("Start over", systemImage: "arrow.counterclockwise")
                    .font(.headline.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .liquidGlass(cornerRadius: 26)
            }
            .buttonStyle(.plain)

            Text("Your answers")
                .font(.title2.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if #available(iOS 26.0, *) {
                    GlassEffectContainer(spacing: 8) {
                        reviewRows
                    }
                } else {
                    reviewRows
                }
            }

            Button {
                Task { await loadResults() }
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
                    .font(.headline.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .liquidGlass(cornerRadius: 26)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .opacity(isLoading ? 0.55 : 1)

            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Finding a good fit...")
                        .font(.subheadline.bold())
                        .foregroundStyle(.secondary)
                }
            }

            if let errorText {
                StatusBubble(title: "No results", text: errorText)
            }
        }
    }

    // MARK: Services / misc

    @ViewBuilder var myServicesOnlyOptions: some View {
        VStack(spacing: 12) {
            Button {
                showServicesSheet = true
            } label: {
                Label("Edit Streaming Services", systemImage: "play.circle")
                    .font(.subheadline.bold())
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .liquidGlass(cornerRadius: 22)
            }
            .buttonStyle(.plain)

            PickForMeOptionButton(title: "My services only", subtitle: nil, isSelected: answers.myServicesOnly == true) {
                answers.myServicesOnly = true
            }
            PickForMeOptionButton(title: "No preference", subtitle: nil, isSelected: answers.myServicesOnly == false) {
                answers.myServicesOnly = false
            }
        }
    }

    var hasEnoughDataForSurprise: Bool {
        model.library.watchedItems.count >= 3
    }

    func scrollToTop(with proxy: ScrollViewProxy) {
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.2)) {
                proxy.scrollTo("pickForMeTop", anchor: .top)
            }
        }
    }
}
