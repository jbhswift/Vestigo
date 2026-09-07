import SwiftUI
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Swipe To Delete Modifier

private struct SwipeToDeleteModifier: ViewModifier {
    let cornerRadius: CGFloat
    let action: () -> Void
    /// When non-nil, the row holds at threshold on swipe (no auto-fly-off) and snaps
    /// back whenever this binding is set to true from outside (e.g. on alert cancel).
    var resetTrigger: Binding<Bool>?
    @State private var offset: CGFloat = 0
    @State private var hasDragged = false
    private let threshold: CGFloat = 72

    func body(content: Content) -> some View {
        ZStack(alignment: .trailing) {
            if offset < -2 {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.red)
                    .frame(width: min(max(0, -offset), threshold * 1.5))
                    .overlay(alignment: .center) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .opacity(min(1.0, max(0, (abs(offset) - 24) / 20)))
                    }
            }

            content
                .offset(x: offset)
                .allowsHitTesting(!hasDragged)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onChanged { value in
                    let dx = value.translation.width
                    let dy = value.translation.height
                    guard dx < 0, abs(dx) > abs(dy) else { return }
                    hasDragged = true
                    withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.85)) {
                        offset = max(-threshold * 1.5, dx)
                    }
                }
                .onEnded { _ in
                    if offset < -threshold {
                        if resetTrigger != nil {
                            // Confirmation mode: hold at threshold, caller resets on cancel
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { offset = -threshold }
                            action()
                        } else {
                            // Immediate mode: fly off then execute
                            withAnimation(.easeIn(duration: 0.16)) { offset = -500 }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) { action() }
                        }
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { offset = 0 }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { hasDragged = false }
                    }
                }
        )
        .onChange(of: resetTrigger?.wrappedValue ?? false) { _, shouldReset in
            guard shouldReset else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { offset = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { hasDragged = false }
            resetTrigger?.wrappedValue = false
        }
    }
}

extension View {
    func swipeToDelete(cornerRadius: CGFloat = 16, action: @escaping () -> Void) -> some View {
        modifier(SwipeToDeleteModifier(cornerRadius: cornerRadius, action: action))
    }

    func swipeToDelete(cornerRadius: CGFloat = 16, resetTrigger: Binding<Bool>, action: @escaping () -> Void) -> some View {
        modifier(SwipeToDeleteModifier(cornerRadius: cornerRadius, action: action, resetTrigger: resetTrigger))
    }
}

// MARK: - LiquidGlass Modifier

struct LiquidGlassModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            content
                .padding(1)
                .glassEffect(.regular, in: shape)
                .overlay { shape.fill(colorScheme == .light ? .black.opacity(0.11) : .clear) }
                .overlay { shape.stroke(colorScheme == .light ? .black.opacity(0.22) : .clear, lineWidth: 1) }
                .clipShape(shape)
                .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 9)
        } else {
            content
                .background {
                    shape
                        .fill(.ultraThinMaterial)
                        .background(shape.fill(colorScheme == .light ? .black.opacity(0.13) : .white.opacity(0.10)))
                        .overlay { shape.stroke(colorScheme == .light ? .black.opacity(0.22) : .white.opacity(0.16), lineWidth: 1) }
                        .shadow(color: .black.opacity(colorScheme == .light ? 0.16 : 0.22), radius: 18, x: 0, y: 10)
                }
                .clipShape(shape)
        }
    }
}

// MARK: - View Modifier Extensions

extension View {
    @ViewBuilder
    func appScrollTouchSafe() -> some View { self }

    func liquidGlass(cornerRadius: CGFloat = 24) -> some View {
        modifier(LiquidGlassModifier(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    func sheetLiquidGlass(cornerRadius: CGFloat = 54) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: shape).clipShape(shape)
                .shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 10)
        } else {
            self.background { shape.fill(.clear).shadow(color: .black.opacity(0.10), radius: 18, x: 0, y: 10) }
                .clipShape(shape)
        }
    }

    @ViewBuilder
    func selectedGlassCapsule(isSelected: Bool) -> some View {
        if isSelected {
            if #available(iOS 26.0, *) {
                self.padding(.horizontal, 1)
                    .background(.white.opacity(0.10), in: Capsule())
                    .glassEffect(.regular, in: Capsule())
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 5)
            } else {
                self.background(.white.opacity(0.18), in: Capsule())
                    .overlay { Capsule().stroke(.white.opacity(0.18), lineWidth: 1) }
            }
        } else {
            self.background(.clear, in: Capsule())
        }
    }

    @ViewBuilder
    func edgeBackGesture(isEnabled: Bool = true, action: @escaping () -> Void) -> some View {
        if isEnabled {
            self.background(alignment: .leading) {
                Color.clear.frame(width: 18).contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 18, coordinateSpace: .global)
                        .onEnded { value in
                            let h = abs(value.translation.width) > abs(value.translation.height) * 2.0
                            if h && value.translation.width > 84 { action() }
                        })
            }
        } else {
            self
        }
    }

    func settingBubble() -> some View {
        self.padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.black.opacity(0.2)) }
            .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1) }
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

// MARK: - ScrollView Touch Tuning

#if canImport(UIKit)
struct ScrollViewTouchTuningView: UIViewRepresentable {
    let axis: Axis.Set
    let alwaysBounce: Bool

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async { configureNearestScrollView(from: view) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { configureNearestScrollView(from: view) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { configureNearestScrollView(from: view) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async { configureNearestScrollView(from: uiView) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { configureNearestScrollView(from: uiView) }
    }

    private func configureNearestScrollView(from view: UIView) {
        var current = view.superview
        while let candidate = current {
            if let scrollView = candidate as? UIScrollView { configure(scrollView); return }
            current = candidate.superview
        }
    }

    private func configure(_ scrollView: UIScrollView) {
        scrollView.panGestureRecognizer.minimumNumberOfTouches = 1
        scrollView.delaysContentTouches = false
        scrollView.canCancelContentTouches = true
        scrollView.keyboardDismissMode = .onDrag
        scrollView.isDirectionalLockEnabled = true
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceVertical = axis == .vertical && alwaysBounce
        scrollView.alwaysBounceHorizontal = axis == .horizontal && alwaysBounce

        let vInset = scrollView.adjustedContentInset.top + scrollView.adjustedContentInset.bottom
        let hInset = scrollView.adjustedContentInset.left + scrollView.adjustedContentInset.right
        let canV = scrollView.contentSize.height + vInset > scrollView.bounds.height + 1
        let canH = scrollView.contentSize.width + hInset > scrollView.bounds.width + 1
        scrollView.isScrollEnabled = true
        scrollView.bounces = alwaysBounce || (axis == .horizontal ? canH : canV)
    }
}

extension View {
    func scrollViewTouchTuning(axis: Axis.Set = .vertical, alwaysBounce: Bool = false) -> some View {
        background(ScrollViewTouchTuningView(axis: axis, alwaysBounce: alwaysBounce))
    }
}
#else
extension View {
    func scrollViewTouchTuning(axis: Axis.Set = .vertical, alwaysBounce: Bool = false) -> some View {
        self
    }
}
#endif
