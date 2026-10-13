import SwiftUI

/// Liquid Glass on iOS 26 (when built with the iOS 26 SDK), materials everywhere else.
extension View {
    @ViewBuilder
    func glassCircle(interactive: Bool = true) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: .circle)
        } else {
            background(.ultraThinMaterial, in: Circle())
        }
        #else
        background(.ultraThinMaterial, in: Circle())
        #endif
    }

    @ViewBuilder
    func glassCapsule(interactive: Bool = true) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: .capsule)
        } else {
            background(.ultraThinMaterial, in: Capsule())
        }
        #else
        background(.ultraThinMaterial, in: Capsule())
        #endif
    }

    @ViewBuilder
    func glassCard(cornerRadius: CGFloat) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        #else
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        #endif
    }

    @ViewBuilder
    func minimizingTabBar() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26, *) { tabBarMinimizeBehavior(.onScrollDown) } else { self }
        #else
        self
        #endif
    }
}
