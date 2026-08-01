#if os(iOS)
import UIKit
#endif

/// Haptic vocabulary: one generator per feel, prepared lazily.
///
/// Unlike `Theme` and `Motion` this must STAY `@MainActor`: `UIFeedbackGenerator`
/// is `NS_SWIFT_UI_ACTOR`, and `enabled` is mutable global state that would be a
/// hard error under `nonisolated`. Do not "fix" this for consistency.
///
/// Off iOS every method is a no-op, and the guard is `os(iOS)` rather than
/// `canImport(UIKit)` for a reason worth knowing: **UIKit imports fine on tvOS,
/// but the feedback generators do not exist there**. The looser guard sent tvOS
/// into this branch and produced four "unavailable in tvOS" errors while the
/// stubs it needed sat unreachable below. `Theme` keeps `canImport(UIKit)`
/// because its UIKit path genuinely works on tvOS, so the same idiom is correct
/// in one file and wrong in the other.
///
/// macOS has `NSHapticFeedbackManager`, which fires in the trackpad rather than
/// the machine and does nothing for someone on a mouse. tvOS has nothing at all.
/// Neither is an honest mapping for "digit entered", so the calls stay and do
/// nothing, and every call site keeps compiling unchanged.
@MainActor
enum Haptics {
    static var enabled = true

    #if os(iOS)

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

    #else

    static func tap() {}
    static func runComplete() {}
    static func error() {}
    static func win() {}
    static func note() {}

    #endif
}
