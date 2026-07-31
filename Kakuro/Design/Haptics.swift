import UIKit

/// Haptic vocabulary: one generator per feel, prepared lazily.
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
