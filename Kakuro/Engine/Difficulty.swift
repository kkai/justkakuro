import Foundation

nonisolated enum Difficulty: String, CaseIterable, Codable, Sendable, Identifiable {
    case easy
    case medium
    case hard

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        }
    }
}

/// Scores a puzzle from the logical solve trace. Higher = harder.
/// Band thresholds are p33/p66 tertiles from DifficultyCalibrationTests
/// (re-run with TEST_RUNNER_KAKURO_CALIBRATE=1 when generation or weights change).
nonisolated enum DifficultyRater {
    static func score(profile: [Technique: Int], solved: Bool) -> Int {
        var score = 0
        for (technique, count) in profile {
            score += weight(for: technique) * count
        }
        if !solved {
            // Required guessing beyond the curriculum: hardest tier.
            score += 500
        }
        return score
    }

    static func weight(for technique: Technique) -> Int {
        switch technique {
        case .duplicateInRun: 1
        case .magicBlock: 2
        case .crossReference: 3
        case .minMaxBounds: 4
        case .nakedSingle: 2
        case .hiddenSingle: 5
        case .combinationReduction: 12
        case .surplusDeficit: 25
        }
    }

    /// Calibrated per-size thresholds: (easyMax, mediumMax). Scores above mediumMax are hard.
    /// p33/p66 tertiles over 30+ generated candidates per size (2026-07-31
    /// calibration run; large is provisional pending a denser-topology rerun).
    static let thresholds: [BoardSize: (easyMax: Int, mediumMax: Int)] = [
        .small: (160, 208),
        .medium: (293, 376),
        .large: (410, 449),
    ]

    static func band(forScore score: Int, size: BoardSize) -> Difficulty {
        guard let t = thresholds[size] else { return .medium }
        if score <= t.easyMax { return .easy }
        if score <= t.mediumMax { return .medium }
        return .hard
    }
}
