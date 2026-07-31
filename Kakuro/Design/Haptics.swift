import UIKit

/// Haptic vocabulary: one generator per feel, prepared lazily.
///
/// Unlike `Theme` and `Motion` this must STAY `@MainActor`: `UIFeedbackGenerator`
/// is `NS_SWIFT_UI_ACTOR`, and `enabled` is mutable global state that would be a
/// hard error under `nonisolated`. Do not "fix" this for consistency.
@MainActor
enum Haptics {
    static var enabled = true

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notify = UINotificationFeedbackGenerator()

    /// Digit entry.
    static func tap() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.7)
    }

    /// Run completed.
    static func runComplete() {
        guard enabled else { return }
        soft.impactOccurred(intensity: 0.9)
    }

    /// Wrong entry wiggle.
    static func error() {
        guard enabled else { return }
        rigid.impactOccurred(intensity: 0.8)
    }

    /// Puzzle solved.
    static func win() {
        guard enabled else { return }
        notify.notificationOccurred(.success)
    }

    /// Note toggle: barely-there tick.
    static func note() {
        guard enabled else { return }
        light.impactOccurred(intensity: 0.4)
    }
}
