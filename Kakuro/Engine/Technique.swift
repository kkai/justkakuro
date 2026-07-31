import Foundation

/// The teaching curriculum. Order is the source of truth for the solver loop,
/// difficulty grading, hint escalation, tutorial sequence, and practice menu.
nonisolated enum Technique: Int, CaseIterable, Codable, Sendable, Comparable, Identifiable {
    case duplicateInRun
    case magicBlock
    case crossReference
    case minMaxBounds
    case nakedSingle
    case hiddenSingle
    case combinationReduction
    case surplusDeficit

    var id: Int { rawValue }

    static func < (lhs: Technique, rhs: Technique) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .duplicateInRun: "No Repeats"
        case .magicBlock: "Magic Blocks"
        case .crossReference: "Cross Reference"
        case .minMaxBounds: "High & Low"
        case .nakedSingle: "Last Candidate"
        case .hiddenSingle: "Only Place"
        case .combinationReduction: "Combination Logic"
        case .surplusDeficit: "Sum Arithmetic"
        }
    }
}

/// Structured facts about one technique application, rendered to prose by TechniqueContent.
nonisolated struct ExplanationData: Codable, Sendable, Equatable {
    /// The run(s) the deduction is about, by id.
    var runIDs: [Int] = []
    /// The digit(s) the deduction concerns.
    var digits: [Int] = []
    /// For magic blocks / combination arguments: the surviving combinations.
    var combinations: [UInt16] = []
}

nonisolated struct Placement: Sendable, Equatable, Codable {
    let position: GridPosition
    let digit: Int
}

nonisolated struct Elimination: Sendable, Equatable, Codable {
    let position: GridPosition
    /// Digits removed, as a bitmask.
    let digits: UInt16
}

/// One concrete application of a technique: what it places, what it eliminates,
/// and what to highlight when teaching it.
nonisolated struct TechniqueApplication: Sendable, Equatable {
    let technique: Technique
    var placements: [Placement] = []
    var eliminations: [Elimination] = []
    var focusCells: [GridPosition] = []
    var involvedRuns: [Int] = []
    var explanation = ExplanationData()
}
