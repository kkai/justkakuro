import Foundation

enum HintLevel: Int, Comparable, Sendable {
    case nudge, technique, highlight, resolution

    static func < (lhs: HintLevel, rhs: HintLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct Hint: Sendable, Equatable {
    let level: HintLevel
    let application: TechniqueApplication
    let text: String
    let highlightCells: [GridPosition]
    /// True when the hint is pointing at a player mistake, not teaching.
    let isErrorHint: Bool
}

/// Escalating, context-aware hints. Errors first; then the next teachable step
/// from the logical solver, revealed a level at a time:
/// nudge (region) → technique (name + rule) → highlight (cells) → resolution.
@MainActor
struct HintEngine {

    /// `showErrors` mirrors the setting: when off, hints teach the next step and
    /// never point out contradictions.
    func hint(for game: KakuroGame, mastery: MasteryTracker, showErrors: Bool = true) -> Hint {
        if showErrors, let errorHint = errorHint(for: game, level: .nudge) {
            return errorHint
        }
        guard let step = LogicalSolver.nextStep(puzzle: game.puzzle, board: game.board) else {
            return Hint(level: .nudge,
                        application: TechniqueApplication(technique: .duplicateInRun),
                        text: "Everything on the board checks out — keep going.",
                        highlightCells: [], isErrorHint: false)
        }
        mastery.recordHint(technique: step.technique, level: .nudge)
        return Hint(level: .nudge,
                    application: step,
                    text: TechniqueContent.nudge(for: step, puzzle: game.puzzle),
                    highlightCells: [], isErrorHint: false)
    }

    func escalate(_ hint: Hint, for game: KakuroGame, mastery: MasteryTracker) -> Hint {
        guard hint.level < .resolution else { return hint }
        let next = HintLevel(rawValue: hint.level.rawValue + 1) ?? .resolution
        if hint.isErrorHint {
            return errorHint(for: game, level: next) ?? hint
        }
        let step = hint.application
        mastery.recordHint(technique: step.technique, level: next)
        let cells = next >= .highlight ? step.focusCells : []
        let text: String
        switch next {
        case .nudge:
            text = hint.text
        case .technique:
            text = TechniqueContent.rule(for: step.technique)
        case .highlight:
            text = TechniqueContent.detail(for: step, puzzle: game.puzzle)
        case .resolution:
            text = TechniqueContent.resolution(for: step, puzzle: game.puzzle)
        }
        return Hint(level: next, application: step, text: text,
                    highlightCells: cells, isErrorHint: false)
    }

    /// Wrong entries take priority over teaching: region first, exact cell later.
    private func errorHint(for game: KakuroGame, level: HintLevel) -> Hint? {
        let wrong = game.puzzle.whitePositions.filter { pos in
            if let entry = game.board.entry(at: pos) {
                return entry != game.puzzle.solution(at: pos)
            }
            return false
        }
        guard let first = wrong.min() else { return nil }
        let runs = game.puzzle.runs(containing: first)
        let region = runs.flatMap(\.cells)
        let application = TechniqueApplication(
            technique: .duplicateInRun,
            focusCells: level >= .resolution ? [first] : region,
            involvedRuns: runs.map(\.id)
        )
        let text: String
        switch level {
        case .nudge, .technique:
            text = "Something doesn't add up in one of the highlighted runs. Check the sums before going further."
        case .highlight:
            text = "One of these cells doesn't match its clues. Re-check each run's sum."
        case .resolution:
            text = "This cell is wrong — clear it and rework the run from its combinations."
        }
        return Hint(level: max(level, .highlight) == level ? level : level,
                    application: application,
                    text: text,
                    highlightCells: level >= .technique ? application.focusCells : [],
                    isErrorHint: true)
    }
}
