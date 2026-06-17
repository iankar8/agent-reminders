import SwiftUI
import AppKit

/// Central animation tokens + a staggered-entrance modifier.
/// One place to tune the feel; every view reads from here.
enum Motion {
    static let panelOpen    = Animation.spring(duration: 0.38, bounce: 0.22)
    static let panelClose   = Animation.spring(duration: 0.20, bounce: 0.0)
    static let listChange   = Animation.spring(duration: 0.28, bounce: 0.0)
    static let hover        = Animation.spring(duration: 0.18, bounce: 0.12)
    static let press        = Animation.spring(duration: 0.12, bounce: 0.0)
    static let resizeReflow = Animation.spring(duration: 0.35, bounce: -0.1)
    static let segThumb     = Animation.spring(duration: 0.34, bounce: 0.0)

    /// Honors System Settings → Accessibility → Reduce Motion.
    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }
}

/// Fades + lifts content in, with a smoothstep-eased per-index delay so rows
/// cascade rather than pop all at once. Collapses to an instant reveal under
/// Reduce Motion.
struct StaggeredAppear: ViewModifier {
    let index: Int
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0)
            .offset(y: on ? 0 : 12)
            .onAppear {
                if Motion.reduceMotion { on = true; return }
                let t = min(Double(index) / 8.0, 1.0)
                let delay = t * t * (3 - 2 * t) * 0.45      // smoothstep, capped at 0.45s
                withAnimation(Motion.panelOpen.delay(delay)) { on = true }
            }
    }
}

extension View {
    func staggered(_ index: Int) -> some View { modifier(StaggeredAppear(index: index)) }
}

extension Comparable {
    /// Clamp self into a closed range.
    func clamped(_ range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
