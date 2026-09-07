import SwiftUI
import Foundation

// MARK: - PickForMeView computed helpers and actions

extension PickForMeView {

    // MARK: Computed helpers

    var currentStep: PickForMeStep {
        steps[min(step, max(steps.count - 1, 0))]
    }

    var secondaryArchetypeOptions: [PickForMeArchetype] {
        PickForMeArchetype.allCases.filter { option in
            option != .surprise && (option == .noPreference || !answers.archetypes.contains(option))
        }
    }

    var dealBreakerOptions: [PickForMeDealBreaker] {
        PickForMeDealBreaker.allCases.filter { option in
            switch option {
            case .documentary:
                return !answers.wantsDocumentary
            case .war:
                return !answers.wantsWar
            default:
                return true
            }
        }
    }

    var currentStepIsAnswered: Bool {
        switch currentStep {
        case .format:
            return answers.mediaFormat != nil
        case .archetype:
            return !answers.archetypes.isEmpty
        case .secondaryArchetypes:
            return !answers.secondaryArchetypes.isEmpty
        case .genrePreferences:
            return !answers.genrePreferences.isEmpty
        case .fictionPreference:
            return answers.fictionPreference != nil
        case .sourceMaterial:
            return answers.sourceMaterial != nil
        case .runtime:
            return true
        case .releaseAge:
            return answers.releaseAge != nil
        case .ageRating:
            return !answers.contentRatings.isEmpty
        case .minimumRating:
            return answers.minimumRating != nil
        case .dealBreakers:
            return !answers.dealBreakers.isEmpty
        case .myServicesOnly:
            return true
        }
    }

    // MARK: Navigation actions

    func advance() {
        guard !isLoading else { return }
        guard currentStepIsAnswered else {
            errorText = "Please choose an answer before continuing."
            return
        }

        if isEditingAnswerFromReview {
            isEditingAnswerFromReview = false
            isReviewingAnswers = true
            errorText = nil
            return
        }

        if step < steps.count - 1 {
            step += 1
        } else {
            Task { await loadResults() }
        }
    }

    func goBack() {
        if isEditingAnswerFromReview {
            isEditingAnswerFromReview = false
            isReviewingAnswers = true
            errorText = nil
            return
        }

        if isReviewingAnswers {
            isReviewingAnswers = false
            errorText = nil
            return
        }

        if !results.isEmpty {
            isReviewingAnswers = true
            isEditingAnswerFromReview = false
        } else if step > 0 {
            step -= 1
        } else {
            dismiss()
        }
    }

    func handleToolbarBack() {
        if isEditingAnswerFromReview || isReviewingAnswers {
            goBack()
        } else {
            dismiss()
        }
    }

    // MARK: Answer management

    func clearCurrentAnswer() {
        switch currentStep {
        case .format:
            answers.mediaFormat = nil
        case .archetype:
            answers.archetypes = []
            answers.secondaryArchetypes = []
        case .secondaryArchetypes:
            answers.secondaryArchetypes = []
        case .genrePreferences:
            answers.genrePreferences = []
        case .fictionPreference:
            answers.fictionPreference = nil
        case .sourceMaterial:
            answers.sourceMaterial = nil
        case .runtime:
            answers.runtimeRange = .unconstrained
        case .releaseAge:
            answers.releaseAge = nil
        case .ageRating:
            answers.contentRatings = []
        case .minimumRating:
            answers.minimumRating = nil
        case .dealBreakers:
            answers.dealBreakers = []
        case .myServicesOnly:
            answers.myServicesOnly = nil
        }

        errorText = nil
    }

    func pruneAgeRatingsForCurrentFormat() {
    }

    func answerSummary(for reviewStep: PickForMeStep) -> String {
        switch reviewStep {
        case .format:
            return answers.mediaFormat?.title ?? "No preference"
        case .archetype:
            return optionTitles(answers.archetypes)
        case .secondaryArchetypes:
            return optionTitles(answers.secondaryArchetypes)
        case .genrePreferences:
            return optionTitles(answers.genrePreferences)
        case .fictionPreference:
            return answers.fictionPreference?.title ?? "No preference"
        case .sourceMaterial:
            return answers.sourceMaterial?.title ?? "No preference"
        case .runtime:
            return answers.runtimeRange.hasConstraint ? answers.runtimeRange.displayString : "No preference"
        case .releaseAge:
            return answers.releaseAge?.title ?? "No preference"
        case .ageRating:
            return optionTitles(answers.contentRatings)
        case .minimumRating:
            return answers.minimumRating?.title ?? "No preference"
        case .dealBreakers:
            return optionTitles(answers.dealBreakers)
        case .myServicesOnly:
            return answers.myServicesOnly == true ? "My services only" : "No preference"
        }
    }

    func optionTitles<Option: PickForMeOption>(_ options: Set<Option>) -> String {
        guard !options.isEmpty else { return "No preference" }
        return options
            .map(\.title)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .joined(separator: ", ")
    }

    // MARK: Results actions

    func loadResults() async {
        let startTime = Date()
        AnalyticsService.shared.track(.pickForMeStarted(format: answers.mediaFormat?.rawValue ?? "any"))
        isLoading = true
        errorText = nil
        let shouldUseFallback = answers.meaningfulQuestionCount == 0
        fallbackText = shouldUseFallback ? "Here are some popular movies and shows instead." : nil
        let queryAnswers = shouldUseFallback ? PickForMeAnswers(mediaFormat: answers.mediaFormat) : answers
        let picked = await model.pickForMeRecommendations(for: queryAnswers)
        isLoading = false

        if picked.isEmpty {
            errorText = "Please repeat the quiz and try different answer combinations."
        } else {
            let duration = Int(Date().timeIntervalSince(startTime))
            AnalyticsService.shared.track(.pickForMeCompleted(resultCount: picked.count, durationSeconds: duration))
            isReviewingAnswers = false
            isEditingAnswerFromReview = false
            results = picked
            resultIndex = 0
            model.pickForMeSessionAnswers = answers
            model.pickForMeSessionResults = picked
            model.savePickForMeRecentSearch(answers)
        }
    }

    func showPreviousResult() {
        guard resultIndex > 0 else { return }
        resultIndex -= 1
    }

    func showNextResult() {
        if resultIndex < results.count - 1 {
            resultIndex += 1
        } else {
            results = []
            resultIndex = 0
            step = 0
        }
    }

    func toggleNeverShowAgainForCurrentResult(_ item: MediaItem) {
        let willHide = !model.library.isNeverShowAgain(item.key)
        model.toggleNeverShowAgain(item)

        guard willHide else { return }
        results.removeAll { $0.key == item.key }

        if results.isEmpty {
            editAnswers()
        } else {
            resultIndex = min(resultIndex, results.count - 1)
        }
    }

    func toggleNotInterestedForCurrentResult(_ item: MediaItem) {
        let willMark = !model.library.isNotInterested(item.key)
        model.toggleNotInterested(item)

        guard willMark else { return }
        results.removeAll { $0.key == item.key }

        if results.isEmpty {
            editAnswers()
        } else {
            resultIndex = min(resultIndex, results.count - 1)
        }
    }

    func editAnswers() {
        isReviewingAnswers = true
        isEditingAnswerFromReview = false
        fallbackText = nil
        errorText = nil
    }

    func startOver() {
        model.pickForMeSessionAnswers = nil
        model.pickForMeSessionResults = []
        answers = PickForMeAnswers()
        results = []
        resultIndex = 0
        step = 0
        isReviewingAnswers = false
        isEditingAnswerFromReview = false
        fallbackText = nil
        errorText = nil
    }
}
