import SwiftUI
import Foundation

// MARK: - Info Sheet

struct PickForMeInfoSheet: View {
    private struct Tip: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let body: String
    }

    private let tips: [Tip] = [
        Tip(
            icon: "theatermasks",
            title: "Primary mood",
            body: "The most important thing you want to feel. If you have multiple moods in mind, pick the most specific or niche one — it anchors every result. The others can go in secondary."
        ),
        Tip(
            icon: "slider.horizontal.3",
            title: "Secondary moods",
            body: "Additional layers that blend alongside the primary. 1 or 2 gives the most focused results. More secondaries add flexibility rather than restricting — but too many dilutes the signal."
        ),
        Tip(
            icon: "circle.hexagongrid",
            title: "Genre flavor",
            body: "A hard requirement. Every single result must genuinely fit the genre or setting you choose. 1 flavor is ideal — each extra one you add is applied simultaneously, which significantly shrinks the pool."
        ),
        Tip(
            icon: "doc.text",
            title: "Fiction or non-fiction",
            body: "Leave this as no preference unless you specifically care — any non-\"no preference\" answer can be very restrictive. \"Based on a true story\" is broad (historical fiction, biopics, documentaries). \"Non-fiction only\" is documentary-strict and will cut most of the library."
        ),
        Tip(
            icon: "star.leadinghalf.filled",
            title: "Minimum rating",
            body: "7.0+ is the sweet spot for quality without cutting too deep. 7.5+ noticeably reduces results in niche genres like space or historical. 8.0+ will often return fewer than 10 results."
        ),
        Tip(
            icon: "calendar",
            title: "Release window",
            body: "Only set this if you genuinely care about the era. Leaving it as any age includes classics that are often the strongest matches. Many niche genres have their best films pre-2000."
        ),
        Tip(
            icon: "hand.thumbsdown",
            title: "Deal breakers",
            body: "Only add things you truly cannot watch. Each cuts an entire category from every result — use them sparingly. Sci-Fi and Heavy fantasy are useful if you want grounded, real-world stories without speculative elements."
        ),
        Tip(
            icon: "book",
            title: "Adaptations",
            body: "Only set this if you specifically want a book or game adaptation. Leave it as no preference otherwise — it restricts results more than most people expect."
        ),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Getting better results")
                    .font(.title2.bold())

                Text("Genre flavor and deal breakers are hard cuts — every extra one reduces the pool. Mood and secondary are layered — more gives Describe It more surface area to match against.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ForEach(tips) { tip in
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: tip.icon)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 28, alignment: .center)
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(tip.title)
                                .font(.subheadline.bold())
                            Text(tip.body)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .liquidGlass(cornerRadius: 20)
                }
            }
            .padding(18)
            .padding(.bottom, 110)
        }
        .scrollClipDisabled()
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

// MARK: - Option Button

struct PickForMeOptionButton: View {
    let title: String
    let subtitle: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.subheadline.bold())
                        .lineLimit(2)

                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.headline.bold())
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .liquidGlass(cornerRadius: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Runtime Range Slider

struct RuntimeRangeSlider: View {
    @Binding var range: PickForMeRuntimeRange
    let accentColor: Color

    @State private var draggingLeft: Bool? = nil
    @State private var isDragging = false

    private let steps = PickForMeRuntimeRange.steps
    private let handleWidth: CGFloat = 36
    private let handleHeight: CGFloat = 24

    private var leftIndex: Int {
        steps.firstIndex(of: range.minMinutes) ?? 0
    }

    private var rightIndex: Int {
        range.maxMinutes == 0 ? steps.count - 1 : (steps.firstIndex(of: range.maxMinutes) ?? steps.count - 1)
    }

    private func xForIndex(_ index: Int, trackWidth: CGFloat) -> CGFloat {
        guard steps.count > 1 else { return 0 }
        return trackWidth * CGFloat(index) / CGFloat(steps.count - 1)
    }

    private func indexForX(_ x: CGFloat, trackWidth: CGFloat) -> Int {
        guard trackWidth > 0, steps.count > 1 else { return 0 }
        let fraction = max(0, min(1, x / trackWidth))
        return Int((fraction * CGFloat(steps.count - 1)).rounded())
    }

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { geo in
                let trackWidth = geo.size.width - handleWidth

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(0.15))
                        .frame(height: 5)
                        .padding(.horizontal, handleWidth / 2)

                    let lx = xForIndex(leftIndex, trackWidth: trackWidth)
                    let rx = xForIndex(rightIndex, trackWidth: trackWidth)
                    Capsule()
                        .fill(accentColor)
                        .frame(width: max(0, rx - lx), height: 5)
                        .offset(x: lx + handleWidth / 2)

                    Capsule()
                        .fill(.white)
                        .frame(width: handleWidth, height: handleHeight)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        .scaleEffect(isDragging && draggingLeft == true ? 0.88 : 1.0)
                        .offset(x: xForIndex(leftIndex, trackWidth: trackWidth))
                        .allowsHitTesting(false)

                    Capsule()
                        .fill(.white)
                        .frame(width: handleWidth, height: handleHeight)
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        .scaleEffect(isDragging && draggingLeft == false ? 0.88 : 1.0)
                        .offset(x: xForIndex(rightIndex, trackWidth: trackWidth))
                        .allowsHitTesting(false)
                }
                .frame(height: handleHeight)
                .coordinateSpace(name: "runtime_slider")
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(coordinateSpace: .named("runtime_slider"))
                        .onChanged { value in
                            let x = value.location.x - handleWidth / 2
                            if draggingLeft == nil {
                                let leftX = xForIndex(leftIndex, trackWidth: trackWidth)
                                let rightX = xForIndex(rightIndex, trackWidth: trackWidth)
                                draggingLeft = abs(x - leftX) <= abs(x - rightX)
                                withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) { isDragging = true }
                            }
                            let newIndex = indexForX(x, trackWidth: trackWidth)
                            if draggingLeft == true {
                                let clamped = max(0, min(newIndex, rightIndex - 1))
                                range = PickForMeRuntimeRange(minMinutes: steps[clamped], maxMinutes: range.maxMinutes)
                            } else {
                                let clamped = max(leftIndex + 1, min(newIndex, steps.count - 1))
                                let newMax = clamped == steps.count - 1 ? 0 : steps[clamped]
                                range = PickForMeRuntimeRange(minMinutes: range.minMinutes, maxMinutes: newMax)
                            }
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { isDragging = false }
                            draggingLeft = nil
                        }
                )
            }
            .frame(height: handleHeight)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Minimum")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(range.minMinutes > 0 ? PickForMeRuntimeRange.formatMinutes(range.minMinutes) : "Any")
                        .font(.subheadline.bold())
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Maximum")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(range.maxMinutes > 0 ? PickForMeRuntimeRange.formatMinutes(range.maxMinutes) : "Any")
                        .font(.subheadline.bold())
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .liquidGlass(cornerRadius: 28)
    }
}
