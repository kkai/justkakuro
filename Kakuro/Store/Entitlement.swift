import Foundation

/// What the one-time unlock buys. Used to give the paywall contextual copy.
nonisolated enum PaidFeature: String, CaseIterable, Sendable, Identifiable {
    case advancedLessons
    case practiceDrills
    case teachingHints
    case largeBoards
    case stats

    var id: String { rawValue }

    var headline: String {
        switch self {
        case .advancedLessons: "The rest of the curriculum"
        case .practiceDrills: "Practice drills"
        case .teachingHints: "Hints that teach"
        case .largeBoards: "Large boards"
        case .stats: "Your progress"
        }
    }

    var pitch: String {
        switch self {
        case .advancedLessons:
            "Six more lessons: Cross Reference, High & Low, Last Candidate, Only Place, Combination Logic and Sum Arithmetic."
        case .practiceDrills:
            "Targeted drills for every technique, with mastery tracking that knows what you've actually earned unaided."
        case .teachingHints:
            "A hint that names the technique and shows you where it applies, instead of filling in the cell for you."
        case .largeBoards:
            "The full-size puzzles, where the deeper techniques start to matter."
        case .stats:
            "Best times, solve counts and your mastery path across all eight techniques."
        }
    }
}

/// Every gating decision in the app, as pure functions. Kept free of StoreKit
/// and of any actor isolation so the rules can be tested exhaustively without a
/// store connection — see `EntitlementTests`.
nonisolated enum FeatureGate {

    /// Free: the rules lesson, No Repeats, and Magic Blocks. Enough to learn the
    /// game and to feel what the hint engine would be doing for you.
    static let freeLessonCeiling: Technique = .magicBlock

    static func isLessonAvailable(_ technique: Technique?, unlocked: Bool) -> Bool {
        guard !unlocked else { return true }
        guard let technique else { return true }  // the rules lesson
        return technique <= freeLessonCeiling
    }

    static func isSizeAvailable(_ size: BoardSize, unlocked: Bool) -> Bool {
        unlocked || size != .large
    }

    /// Difficulty is never gated — a free player can play Hard on a small board.
    static func isDifficultyAvailable(_ difficulty: Difficulty, unlocked: Bool) -> Bool {
        true
    }

    static func isAvailable(_ feature: PaidFeature, unlocked: Bool) -> Bool {
        unlocked
    }
}
