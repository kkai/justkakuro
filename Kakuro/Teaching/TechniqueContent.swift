import Foundation

/// All teaching copy: renders a TechniqueApplication's structured facts into
/// short, plain-language explanations. One voice everywhere: direct, concrete,
/// never mystical about "logic".
nonisolated enum TechniqueContent {

    // MARK: - Per-technique rule (the one-liner shown at hint level 2)

    static func rule(for technique: Technique) -> String {
        switch technique {
        case .duplicateInRun:
            "A digit can appear only once in a run. Anything already placed is off the table for the rest of its row and column runs."
        case .magicBlock:
            "Some sums have exactly one set of digits. That's a magic block: a 2-cell 17 can only be 8+9, and a 3-cell 6 can only be 1+2+3."
        case .crossReference:
            "Every cell belongs to two runs. Only digits possible in both the across run and the down run can go there."
        case .minMaxBounds:
            "Check what the rest of the run can still add up to. If a digit would push the sum too high or leave it unreachable, it's out."
        case .nakedSingle:
            "When only one candidate is left in a cell, that's the answer. Place it."
        case .hiddenSingle:
            "If a digit the run needs fits in only one of its cells, it must go there, whatever else that cell could be."
        case .combinationReduction:
            "Play the remaining combinations against each other: a digit that appears in no workable arrangement can be crossed off."
        case .surplusDeficit:
            "Add up what's certain and subtract from the clue. When one cell is left, arithmetic hands you its digit."
        }
    }

    /// A short lesson paragraph for tutorials and the practice menu.
    static func lesson(for technique: Technique) -> String {
        switch technique {
        case .duplicateInRun:
            "Kakuro's one hard rule inside a run: no digit repeats. Every placement you make immediately narrows its row run and its column run. Make that your reflex: place a digit, then sweep both runs."
        case .magicBlock:
            "The fastest wins in Kakuro come from sums with a single possible digit set. Learn the short list (3, 4, 16, 17 in two cells; 6, 7, 23, 24 in three) and scan for them first. They anchor everything else."
        case .crossReference:
            "A cell answers to two clues at once. Work out the digits its across run allows, then its down run, and keep only the overlap. Where a magic block crosses another run, this often pins a cell exactly."
        case .minMaxBounds:
            "Every partial run leaves a remainder. If two cells must make 6, no cell can hold 7. If they must make 16, nothing below 7 works. High and low bounds quietly rule out most of the pad."
        case .nakedSingle:
            "Keep notes as you go. The moment eliminations leave one candidate in a cell, it's decided. Enter it and let the new digit ripple through both runs."
        case .hiddenSingle:
            "Sometimes a cell has options, but the run doesn't. If every remaining combination needs a 9 and only one cell can still take it, the 9 is placed for you."
        case .combinationReduction:
            "When simple checks stall, line up the run's surviving combinations and try to arrange them against the crossing constraints. Digits that appear in no arrangement are gone, and runs often collapse entirely."
        case .surplusDeficit:
            "Totals are information. Sum the certain cells, subtract from the clue, and the remainder belongs to whatever is left. On tangled boards this arithmetic cracks cells no elimination can reach."
        }
    }

    // MARK: - Contextual copy for a concrete application

    static func nudge(for step: TechniqueApplication, puzzle: KakuroPuzzle) -> String {
        let place = regionPhrase(for: step, puzzle: puzzle)
        switch step.technique {
        case .duplicateInRun:
            return "A digit already on the board is doing more work than you've used \(place)."
        case .magicBlock:
            return "There's a magic block \(place), a sum with only one possible digit set."
        case .crossReference:
            return "Two clues overlap \(place); their crossing narrows a cell nicely."
        case .minMaxBounds:
            return "The remaining sum \(place) is tighter than it looks."
        case .nakedSingle:
            return "A cell \(place) is down to its last candidate."
        case .hiddenSingle:
            return "A run \(place) needs a digit that has only one home."
        case .combinationReduction:
            return "Compare the surviving combinations \(place). They agree on more than you'd think."
        case .surplusDeficit:
            return "Try the arithmetic \(place): the certain cells nearly settle the run."
        }
    }

    static func detail(for step: TechniqueApplication, puzzle: KakuroPuzzle) -> String {
        switch step.technique {
        case .duplicateInRun:
            let digits = list(step.explanation.digits)
            return "The highlighted run already contains \(digits). Cross \(step.explanation.digits.count == 1 ? "it" : "them") out of the empty cells."
        case .magicBlock:
            if let combo = step.explanation.combinations.first {
                let digits = list(DigitSet.digits(combo))
                let run = step.involvedRuns.first.map { puzzle.runs[$0] }
                let sum = run.map { "\($0.sum)" } ?? "this sum"
                return "\(sum) in \(run?.length ?? 0) cells works only as \(digits). Note those digits. Nothing else can enter this run."
            }
            return rule(for: .magicBlock)
        case .crossReference:
            let digits = list(step.explanation.digits)
            return "Where these two runs cross, only \(digits) satisfy both clues."
        case .minMaxBounds:
            let digits = list(step.explanation.digits)
            return "Given what the rest of the run can still hold, \(digits) can't fit in the highlighted cell."
        case .nakedSingle:
            if let placement = step.placements.first {
                return "Only \(placement.digit) is left for the highlighted cell."
            }
            return rule(for: .nakedSingle)
        case .hiddenSingle:
            if let placement = step.placements.first {
                return "Every combination for this run includes \(placement.digit), and only the highlighted cell can take it."
            }
            return rule(for: .hiddenSingle)
        case .combinationReduction:
            return "Arranging the run's remaining combinations against the crossing runs rules out the crossed digits."
        case .surplusDeficit:
            if let placement = step.placements.first {
                return "Subtract the settled cells from the clue: the highlighted cell must be \(placement.digit)."
            }
            return rule(for: .surplusDeficit)
        }
    }

    static func resolution(for step: TechniqueApplication, puzzle: KakuroPuzzle) -> String {
        if let placement = step.placements.first {
            return "\(detail(for: step, puzzle: puzzle)) Tap Apply to place \(placement.digit)."
        }
        return "\(detail(for: step, puzzle: puzzle)) Tap Apply to update the notes."
    }

    // MARK: - Helpers

    private static func regionPhrase(for step: TechniqueApplication, puzzle: KakuroPuzzle) -> String {
        guard let cell = step.focusCells.first ?? step.placements.first?.position else {
            return "on the board"
        }
        let third = puzzle.rows / 3
        let vertical = cell.row <= third ? "top" : (cell.row > puzzle.rows - third - 1 ? "bottom" : "middle")
        let horizontal = cell.col <= third ? "left" : (cell.col > puzzle.cols - third - 1 ? "right" : "center")
        if vertical == "middle" && horizontal == "center" {
            return "in the middle of the board"
        }
        return "in the \(vertical) \(horizontal)"
    }

    private static func list(_ digits: [Int]) -> String {
        let strings = digits.map(String.init)
        switch strings.count {
        case 0: return "nothing"
        case 1: return strings[0]
        case 2: return "\(strings[0]) and \(strings[1])"
        default: return strings.dropLast().joined(separator: ", ") + " and " + strings.last!
        }
    }
}
