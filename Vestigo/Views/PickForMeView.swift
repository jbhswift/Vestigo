import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(WebKit)
import WebKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

struct PickForMeView: View {
    @ObservedObject var model: VestigoModel
    let startingFilter: MediaFilter
    @Environment(\.dismiss) var dismiss
    @State var answers: PickForMeAnswers
    @State var step = 0
    @State var results: [MediaItem] = []
    @State var resultIndex = 0
    @State var resultDragOffset: CGFloat = 0
    @State var screenWidth: CGFloat = 393
    @State var isLoading = false
    @State var errorText: String?
    @State var fallbackText: String?
    @State var isReviewingAnswers = false
    @State var isEditingAnswerFromReview = false
    @State var showingInfoSheet = false
    @State var showServicesSheet = false
    @State var scrollToBottomToken = UUID()
    @AppStorage("Vestigo.devMode") var devMode: Bool = false

    var steps: [PickForMeStep] {
        PickForMeStep.steps(for: answers)
    }

    init(model: VestigoModel, startingFilter: MediaFilter) {
        self.model = model
        self.startingFilter = startingFilter
        if let saved = model.pickForMeSessionAnswers {
            self._answers = State(initialValue: saved)
            self._results = State(initialValue: model.pickForMeSessionResults)
            self._isReviewingAnswers = State(initialValue: true)
        } else {
            self._answers = State(initialValue: PickForMeAnswers())
        }
    }

    var body: some View {
        ZStack {
            AppBackground(settings: model.settings)
                .ignoresSafeArea()

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    Color.clear
                        .frame(height: 0)
                        .id("pickForMeTop")

                    VStack(alignment: .leading, spacing: 24) {
                        header
                        mainContent
                    }
                    .padding(16)
                    .padding(.bottom, 28)
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    Color.clear.frame(height: 0).id("pickForMeBottom")
                }
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .vertical)
                .onChange(of: step) { _, _ in
                    scrollToTop(with: proxy)
                }
                .onChange(of: resultIndex) { _, _ in
                    scrollToTop(with: proxy)
                }
                .onChange(of: results.isEmpty) { _, _ in
                    scrollToTop(with: proxy)
                }
                .onChange(of: scrollToBottomToken) { _, _ in
                    withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo("pickForMeBottom", anchor: .bottom) }
                }
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 30, coordinateSpace: .global)
                .onChanged { value in
                    guard !results.isEmpty, !isEditingAnswerFromReview, !isReviewingAnswers else { return }
                    guard value.startLocation.x > 50 else { return }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) * 0.7 else { return }
                    resultDragOffset = dx * 0.75
                }
                .onEnded { value in
                    guard !results.isEmpty, !isEditingAnswerFromReview, !isReviewingAnswers else {
                        withAnimation(.spring(response: 0.3)) { resultDragOffset = 0 }
                        return
                    }
                    guard value.startLocation.x > 50 else {
                        withAnimation(.spring(response: 0.3)) { resultDragOffset = 0 }
                        return
                    }
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard abs(dx) > abs(dy) * 1.5, abs(dx) > 50 else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { resultDragOffset = 0 }
                        return
                    }
                    let goRight = dx > 0
                    let screenWidth = self.screenWidth
                    withAnimation(.easeIn(duration: 0.15)) {
                        resultDragOffset = goRight ? screenWidth : -screenWidth
                    }
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        if goRight { showPreviousResult() } else { showNextResult() }
                        resultDragOffset = goRight ? -screenWidth : screenWidth
                        withAnimation(.easeOut(duration: 0.2)) { resultDragOffset = 0 }
                    }
                }
        )
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { screenWidth = $0 }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    handleToolbarBack()
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
            }
        }
        .onChange(of: answers.mediaFormat) { _, _ in
            if answers.isSeriesOnly {
                answers.runtimeRange = .unconstrained
            }

            if step >= steps.count {
                step = max(steps.count - 1, 0)
            }
        }
        .onChange(of: answers.archetypes) { _, newValue in
            answers.secondaryArchetypes.subtract(newValue)
            if newValue.contains(.documentary) {
                answers.dealBreakers.remove(.documentary)
            }
            if newValue.contains(.war) {
                answers.dealBreakers.remove(.war)
            }
            if step >= steps.count {
                step = max(steps.count - 1, 0)
            }
        }
        .onChange(of: answers.secondaryArchetypes) { _, newValue in
            if newValue.contains(.documentary) {
                answers.dealBreakers.remove(.documentary)
            }
            if newValue.contains(.war) {
                answers.dealBreakers.remove(.war)
            }
            if step >= steps.count {
                step = max(steps.count - 1, 0)
            }
        }
        .onChange(of: answers.contentRatings) { _, _ in
            if step >= steps.count {
                step = max(steps.count - 1, 0)
            }
        }
        .sheet(isPresented: $showServicesSheet) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Text("Streaming Services")
                            .font(.title2.bold())
                        Spacer()
                        Button("Done") { showServicesSheet = false }
                            .fontWeight(.semibold)
                    }
                    StreamingServicesPicker(model: model)
                }
                .padding(18)
                .padding(.bottom, 110)
            }
            .scrollClipDisabled()
            .scrollDismissesKeyboard(.immediately)
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) {
                Capsule()
                    .fill(.white.opacity(0.46))
                    .frame(width: 48, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                    .background(.clear)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .sheetLiquidGlass(cornerRadius: 48)
            .ignoresSafeArea(edges: .bottom)
            .presentationBackground(.clear)
            .presentationCornerRadius(54)
        }
    }

}
