import SwiftUI
import Foundation

struct CarouselOrderContent: View {
    @ObservedObject var model: VestigoModel

    private var totalRowCount: Int {
        model.settings.homeCarouselOrder.count + model.settings.recommendationCarouselOrder.count
    }

    var body: some View {
        List {
            ForEach(model.settings.homeCarouselOrder, id: \.self) { carousel in
                CarouselOrderRow(
                    title: carousel.title,
                    isHidden: model.settings.homeCarouselHidden.contains(carousel),
                    accentColor: model.settings.accentColor,
                    toggle: {
                        if model.settings.homeCarouselHidden.contains(carousel) {
                            model.settings.homeCarouselHidden.remove(carousel)
                        } else {
                            model.settings.homeCarouselHidden.insert(carousel)
                        }
                    }
                )
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(.primary.opacity(0.1))
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
            .onMove { indices, newOffset in
                model.settings.homeCarouselOrder.move(fromOffsets: indices, toOffset: newOffset)
            }

            ForEach(model.settings.recommendationCarouselOrder, id: \.self) { carousel in
                CarouselOrderRow(
                    title: carousel.title,
                    isHidden: model.settings.recommendationCarouselHidden.contains(carousel),
                    accentColor: model.settings.accentColor,
                    toggle: {
                        if model.settings.recommendationCarouselHidden.contains(carousel) {
                            model.settings.recommendationCarouselHidden.remove(carousel)
                        } else {
                            model.settings.recommendationCarouselHidden.insert(carousel)
                        }
                    }
                )
                .listRowBackground(Color.clear)
                .listRowSeparatorTint(.primary.opacity(0.1))
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            }
            .onMove { indices, newOffset in
                model.settings.recommendationCarouselOrder.move(fromOffsets: indices, toOffset: newOffset)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDisabled(true)
        .environment(\.editMode, .constant(.active))
        .frame(height: CGFloat(totalRowCount) * 50 + 16)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .liquidGlass(cornerRadius: 28)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


struct CarouselOrderRow: View {
    let title: String
    let isHidden: Bool
    let accentColor: Color
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.subheadline.bold())
                .foregroundStyle(isHidden ? .secondary : .primary)

            Spacer()

            Button(action: toggle) {
                Image(systemName: isHidden ? "eye.slash" : "eye")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isHidden ? .secondary : accentColor)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isHidden ? "Show \(title)" : "Hide \(title)")
        }
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
