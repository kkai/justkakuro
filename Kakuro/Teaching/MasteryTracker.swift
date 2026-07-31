import Foundation
import Observation

/// Tracks how well the player knows each technique, Good Sudoku-style:
/// unaided applications advance mastery, hints delay it.
@Observable @MainActor
final class MasteryTracker {

    enum MasteryState: String, Codable, Comparable {
        case locked, introduced, practicing, learned

        private var order: Int {
            switch self {
            case .locked: 0
            case .introduced: 1
            case .practicing: 2
            case .learned: 3
            }
        }

        static func < (lhs: MasteryState, rhs: MasteryState) -> Bool {
            lhs.order < rhs.order
        }
    }

    struct Record: Codable, Equatable {
        var state: MasteryState = .locked
        var unaidedUses = 0
        var hintedUses = 0
        var drillsCompleted = 0
        var lessonCompleted = false
    }

    /// Unaided applications needed to reach `.learned`.
    static let learnedThreshold = 5

    private(set) var records: [Technique: Record] = [:]
    private let store: ProgressStore?

    init(store: ProgressStore? = nil) {
        self.store = store
        if let saved = store?.loadMastery([Technique: Record].self) {
            records = saved
        } else {
            // The first two techniques start available; the rest unlock in order.
            records[.duplicateInRun] = Record(state: .introduced)
            records[.magicBlock] = Record(state: .introduced)
        }
    }

    func record(for technique: Technique) -> Record {
        records[technique] ?? Record()
    }

    func state(of technique: Technique) -> MasteryState {
        record(for: technique).state
    }

    // MARK: - Events

    /// The player asked for a hint on this technique.
    func recordHint(technique: Technique, level: HintLevel) {
        var rec = record(for: technique)
        if rec.state == .locked { rec.state = .introduced }
        if level >= .highlight {
            rec.hintedUses += 1
        }
        records[technique] = rec
        persist()
    }

    /// The player made an entry; if it matches the step the solver was about to
    /// take, that counts as an unaided application of the technique.
    func recordEntry(position: GridPosition, digit: Int, game: KakuroGame) {
        guard game.puzzle.solution(at: position) == digit,
              let previous = game.boardBeforeLastMove,
              previous.entry(at: position) == nil
        else { return }
        // Walk the solver forward from the pre-move state. Elimination steps
        // don't change entries, so skip past them to the placement they lead to,
        // remembering what they cost: the player who placed this digit had to do
        // every deduction in that chain. Credit the hardest one — the binding
        // constraint — so elimination techniques can be learned through play and
        // not only through drills.
        var board = previous
        var chain: [Technique] = []
        for _ in 0..<32 {
            guard let step = LogicalSolver.nextStep(puzzle: game.puzzle, board: board) else { return }
            if step.placements.contains(Placement(position: position, digit: digit)) {
                chain.append(step.technique)
                // Rank by solving cost, not curriculum position: nakedSingle is
                // taught late but is the trivial "one candidate left" step, so
                // ordering by rawValue would credit it over the elimination work
                // that actually earned the placement.
                let hardest = chain.max { DifficultyRater.weight(for: $0) < DifficultyRater.weight(for: $1) }
                advance(technique: hardest ?? step.technique)
                return
            }
            guard step.placements.isEmpty else { return }
            chain.append(step.technique)
            let before = board
            LogicalSolver.applyEliminations(step, to: &board)
            if board == before { return }
        }
    }

    func recordLessonCompleted(_ technique: Technique) {
        var rec = record(for: technique)
        rec.lessonCompleted = true
        if rec.state < .practicing { rec.state = .practicing }
        records[technique] = rec
        unlockNext(after: technique)
        persist()
    }

    func recordDrillCompleted(_ technique: Technique, unaided: Bool) {
        var rec = record(for: technique)
        rec.drillsCompleted += 1
        if unaided { rec.unaidedUses += 1 }
        records[technique] = rec
        promoteIfEarned(technique)
        persist()
    }

    private func advance(technique: Technique) {
        var rec = record(for: technique)
        rec.unaidedUses += 1
        if rec.state == .locked { rec.state = .introduced }
        records[technique] = rec
        promoteIfEarned(technique)
        persist()
    }

    private func promoteIfEarned(_ technique: Technique) {
        var rec = record(for: technique)
        if rec.unaidedUses >= Self.learnedThreshold, rec.state < .learned {
            rec.state = .learned
            records[technique] = rec
            unlockNext(after: technique)
        }
    }

    private func unlockNext(after technique: Technique) {
        guard let next = Technique(rawValue: technique.rawValue + 1) else { return }
        var rec = record(for: next)
        if rec.state == .locked {
            rec.state = .introduced
            records[next] = rec
        }
    }

    private func persist() {
        store?.saveMastery(records)
    }
}
