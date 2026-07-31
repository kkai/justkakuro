import Foundation

/// Human-style solver. Applies the cheapest applicable technique (curriculum
/// order) to a candidate grid until solved or stuck. The same `nextStep` code
/// path grades difficulty during generation and powers the in-game hint engine
/// against the player's actual entries and notes.
nonisolated struct LogicalSolver: Sendable {

    struct SolveResult: Sendable {
        let solved: Bool
        let trace: [TechniqueApplication]
        var histogram: [Technique: Int] {
            trace.reduce(into: [:]) { $0[$1.technique, default: 0] += 1 }
        }
    }

    /// Candidate state for a solve: entries plus per-cell candidate bitmasks.
    struct State: Sendable {
        var entries: [GridPosition: Int]
        var candidates: [GridPosition: UInt16]

        init(puzzle: KakuroPuzzle, board: BoardState? = nil) {
            entries = board?.entries ?? [:]
            candidates = [:]
            for pos in puzzle.whitePositions where entries[pos] == nil {
                candidates[pos] = DigitSet.all
            }
            // Seed candidates from the player's notes where present: notes are
            // the player's visible knowledge, so hints never re-teach them.
            if let board {
                for (pos, notes) in board.notes where entries[pos] == nil && !notes.isEmpty {
                    candidates[pos] = DigitSet.fromDigits(notes)
                }
            }
        }
    }

    // MARK: - Full solve (generation / grading)

    static func solve(_ puzzle: KakuroPuzzle) -> SolveResult {
        var state = State(puzzle: puzzle)
        var trace: [TechniqueApplication] = []
        while let step = nextStep(puzzle: puzzle, state: &state, apply: true) {
            trace.append(step)
            if state.candidates.isEmpty { break }
        }
        let solved = puzzle.whitePositions.allSatisfy { state.entries[$0] != nil }
        return SolveResult(solved: solved, trace: trace)
    }

    // MARK: - Next step (hints)

    /// Finds the next applicable technique for the player's board without mutating it.
    static func nextStep(puzzle: KakuroPuzzle, board: BoardState) -> TechniqueApplication? {
        var state = State(puzzle: puzzle, board: board)
        return nextStep(puzzle: puzzle, state: &state, apply: false)
    }

    /// Core dispatch: tries techniques in curriculum order, returns the first
    /// that makes progress. When `apply` is true the step is applied to `state`.
    static func nextStep(puzzle: KakuroPuzzle, state: inout State, apply: Bool) -> TechniqueApplication? {
        let detectors: [(inout State) -> TechniqueApplication?] = [
            { detectDuplicateInRun(puzzle: puzzle, state: &$0) },
            { detectMagicBlock(puzzle: puzzle, state: &$0) },
            { detectCrossReference(puzzle: puzzle, state: &$0) },
            { detectMinMaxBounds(puzzle: puzzle, state: &$0) },
            { detectNakedSingle(puzzle: puzzle, state: &$0) },
            { detectHiddenSingle(puzzle: puzzle, state: &$0) },
            { detectCombinationReduction(puzzle: puzzle, state: &$0) },
            { detectSurplusDeficit(puzzle: puzzle, state: &$0) },
        ]
        for detector in detectors {
            var probe = state
            if let step = detector(&probe) {
                if apply {
                    applyStep(step, to: &state)
                }
                return step
            }
        }
        return nil
    }

    /// Applies a step's eliminations to a board's notes, seeding notes from the
    /// step's own candidate view where a cell has none yet. Lets callers replay
    /// the solver's reasoning over a player board.
    static func applyEliminations(_ step: TechniqueApplication, to board: inout BoardState) {
        for elimination in step.eliminations {
            let removed = Set(DigitSet.digits(elimination.digits))
            let old = board.notes(at: elimination.position)
            let base = old.isEmpty ? Set(DigitSet.digits(DigitSet.all)) : old
            let new = base.subtracting(removed)
            board.notes[elimination.position] = new.isEmpty ? nil : new
        }
    }

    static func applyStep(_ step: TechniqueApplication, to state: inout State) {
        for elimination in step.eliminations {
            if var cands = state.candidates[elimination.position] {
                cands &= ~elimination.digits
                state.candidates[elimination.position] = cands
            }
        }
        for placement in step.placements {
            state.entries[placement.position] = placement.digit
            state.candidates[placement.position] = nil
        }
    }

    // MARK: - Helpers

    private static func usedDigits(in run: Run, state: State) -> UInt16 {
        run.cells.reduce(UInt16(0)) { mask, pos in
            if let d = state.entries[pos] { return mask | DigitSet.mask(d) }
            return mask
        }
    }

    private static func openCells(in run: Run, state: State) -> [GridPosition] {
        run.cells.filter { state.entries[$0] == nil }
    }

    // MARK: - Technique detectors
    // Each returns the first useful application found, or nil. "Useful" means
    // it eliminates at least one candidate that is currently present, or
    // places a digit.

    /// A placed digit removes itself from candidates elsewhere in its runs.
    static func detectDuplicateInRun(puzzle: KakuroPuzzle, state: inout State) -> TechniqueApplication? {
        for run in puzzle.runs {
            let used = usedDigits(in: run, state: state)
            guard used != 0 else { continue }
            var eliminations: [Elimination] = []
            for pos in openCells(in: run, state: state) {
                let cands = state.candidates[pos] ?? DigitSet.all
                let removable = cands & used
                if removable != 0 {
                    eliminations.append(Elimination(position: pos, digits: removable))
                }
            }
            if !eliminations.isEmpty {
                return TechniqueApplication(
                    technique: .duplicateInRun,
                    eliminations: eliminations,
                    focusCells: run.cells,
                    involvedRuns: [run.id],
                    explanation: ExplanationData(runIDs: [run.id], digits: DigitSet.digits(used))
                )
            }
        }
        return nil
    }

    /// Runs whose (sum, length) admit few combinations restrict cell candidates
    /// to the union of remaining combinations. The classic teaching case is the
    /// unique combination ("magic block").
    static func detectMagicBlock(puzzle: KakuroPuzzle, state: inout State) -> TechniqueApplication? {
        for run in puzzle.runs {
            let used = usedDigits(in: run, state: state)
            let combos = SumCombinations.combinations(sum: run.sum, length: run.length, usedDigits: used)
            // Teach as "magic block" only when the digit set is fully determined.
            guard combos.count == 1, let combo = combos.first else { continue }
            let allowed = combo & ~used
            var eliminations: [Elimination] = []
            for pos in openCells(in: run, state: state) {
                let cands = state.candidates[pos] ?? DigitSet.all
                let removable = cands & ~allowed
                if removable != 0 {
                    eliminations.append(Elimination(position: pos, digits: removable))
                }
            }
            if !eliminations.isEmpty {
                return TechniqueApplication(
                    technique: .magicBlock,
                    eliminations: eliminations,
                    focusCells: run.cells,
                    involvedRuns: [run.id],
                    explanation: ExplanationData(
                        runIDs: [run.id],
                        digits: DigitSet.digits(allowed),
                        combinations: [combo]
                    )
                )
            }
        }
        return nil
    }

    /// A cell's candidates are the intersection of what its across run and its
    /// down run allow. Taught on cells where the intersection removes digits.
    static func detectCrossReference(puzzle: KakuroPuzzle, state: inout State) -> TechniqueApplication? {
        for (pos, cands) in state.candidates.sorted(by: { $0.key < $1.key }) {
            guard let pair = puzzle.runIndex[pos],
                  let acrossID = pair.across, let downID = pair.down else { continue }
            let across = puzzle.runs[acrossID]
            let down = puzzle.runs[downID]
            let acrossUnion = SumCombinations.remainingUnion(
                sum: across.sum, length: across.length, usedDigits: usedDigits(in: across, state: state))
            let downUnion = SumCombinations.remainingUnion(
                sum: down.sum, length: down.length, usedDigits: usedDigits(in: down, state: state))
            let allowed = acrossUnion & downUnion
            let removable = cands & ~allowed
            if removable != 0 {
                return TechniqueApplication(
                    technique: .crossReference,
                    eliminations: [Elimination(position: pos, digits: removable)],
                    focusCells: [pos],
                    involvedRuns: [acrossID, downID],
                    explanation: ExplanationData(
                        runIDs: [acrossID, downID],
                        digits: DigitSet.digits(allowed)
                    )
                )
            }
        }
        return nil
    }

    /// Remaining-sum bounds: in a partially filled run, each open cell's digit
    /// plus the min/max of the other open cells must reach the remaining sum.
    static func detectMinMaxBounds(puzzle: KakuroPuzzle, state: inout State) -> TechniqueApplication? {
        for run in puzzle.runs {
            let open = openCells(in: run, state: state)
            guard !open.isEmpty else { continue }
            let used = usedDigits(in: run, state: state)
            let placedSum = DigitSet.sum(used)
            let rest = run.sum - placedSum
            for pos in open {
                let cands = state.candidates[pos] ?? DigitSet.all
                var allowed: UInt16 = 0
                let others = open.filter { $0 != pos }
                for digit in DigitSet.digits(cands) {
                    if DigitSet.contains(used, digit) { continue }
                    let need = rest - digit
                    if others.isEmpty {
                        if need == 0 { allowed |= DigitSet.mask(digit) }
                    } else {
                        let otherSets = others.map { state.candidates[$0] ?? DigitSet.all }
                        let excluding = DigitSet.mask(digit) | used
                        let bounds: (min: Int?, max: Int?)
                        if others.count <= 4 {
                            // Exact system-of-distinct-representatives bounds.
                            bounds = (minAchievableSum(otherSets, excluding: excluding),
                                      maxAchievableSum(otherSets, excluding: excluding))
                        } else {
                            // Loose union bounds (superset of the exact range, so
                            // eliminations stay sound) — exact search would explode.
                            bounds = looseSumBounds(otherSets, excluding: excluding)
                        }
                        if let minSum = bounds.min, let maxSum = bounds.max,
                           need >= minSum, need <= maxSum {
                            allowed |= DigitSet.mask(digit)
                        }
                    }
                }
                let removable = cands & ~allowed
                if removable != 0 {
                    return TechniqueApplication(
                        technique: .minMaxBounds,
                        eliminations: [Elimination(position: pos, digits: removable)],
                        focusCells: run.cells,
                        involvedRuns: [run.id],
                        explanation: ExplanationData(runIDs: [run.id], digits: DigitSet.digits(removable))
                    )
                }
            }
        }
        return nil
    }

    /// One candidate left in a cell: place it.
    static func detectNakedSingle(puzzle: KakuroPuzzle, state: inout State) -> TechniqueApplication? {
        for (pos, cands) in state.candidates.sorted(by: { $0.key < $1.key }) {
            if DigitSet.count(cands) == 1, let digit = DigitSet.digits(cands).first {
                return TechniqueApplication(
                    technique: .nakedSingle,
                    placements: [Placement(position: pos, digit: digit)],
                    focusCells: [pos],
                    involvedRuns: puzzle.runs(containing: pos).map(\.id),
                    explanation: ExplanationData(digits: [digit])
                )
            }
        }
        return nil
    }

    /// A digit that must appear in a run fits only one of its open cells.
    static func detectHiddenSingle(puzzle: KakuroPuzzle, state: inout State) -> TechniqueApplication? {
        for run in puzzle.runs {
            let open = openCells(in: run, state: state)
            guard open.count > 1 else { continue }
            let used = usedDigits(in: run, state: state)
            let combos = SumCombinations.combinations(sum: run.sum, length: run.length, usedDigits: used)
            guard !combos.isEmpty else { continue }
            // Digits required by every remaining combination must be placed somewhere.
            let required = combos.reduce(DigitSet.all) { $0 & $1 } & ~used
            for digit in DigitSet.digits(required) {
                let fits = open.filter { DigitSet.contains(state.candidates[$0] ?? 0, digit) }
                if fits.count == 1, let pos = fits.first {
                    return TechniqueApplication(
                        technique: .hiddenSingle,
                        placements: [Placement(position: pos, digit: digit)],
                        focusCells: run.cells,
                        involvedRuns: [run.id],
                        explanation: ExplanationData(runIDs: [run.id], digits: [digit])
                    )
                }
            }
        }
        return nil
    }

    /// Deeper combination logic: enumerate assignments of remaining combinations
    /// to a run's open cells (respecting current candidates) and prune digits
    /// that appear in no consistent assignment.
    static func detectCombinationReduction(puzzle: KakuroPuzzle, state: inout State) -> TechniqueApplication? {
        for run in puzzle.runs {
            let open = openCells(in: run, state: state)
            // Cap enumeration size: beyond 6 open cells the assignment count can
            // explode; longer runs get resolved by cheaper techniques first.
            guard open.count >= 2, open.count <= 6 else { continue }
            let used = usedDigits(in: run, state: state)
            let combos = SumCombinations.combinations(sum: run.sum, length: run.length, usedDigits: used)
            guard !combos.isEmpty else { continue }
            var achievable: [GridPosition: UInt16] = [:]
            for combo in combos {
                let free = combo & ~used
                accumulateAssignments(cells: open, digits: free, state: state, into: &achievable)
            }
            var eliminations: [Elimination] = []
            for pos in open {
                let cands = state.candidates[pos] ?? DigitSet.all
                let removable = cands & ~(achievable[pos] ?? 0)
                if removable != 0 {
                    eliminations.append(Elimination(position: pos, digits: removable))
                }
            }
            if !eliminations.isEmpty {
                return TechniqueApplication(
                    technique: .combinationReduction,
                    eliminations: eliminations,
                    focusCells: run.cells,
                    involvedRuns: [run.id],
                    explanation: ExplanationData(runIDs: [run.id], combinations: combos)
                )
            }
        }
        return nil
    }

    /// The 45-rule analog: for each clue cell region comparison we use the
    /// simplest useful version — comparing a run's sum against the total of
    /// crossing unique-combination runs to force a single cell. Implemented as
    /// pairwise run arithmetic: if all but one cell of a run lie in runs whose
    /// digit sets are fully determined, the remaining cell is forced.
    static func detectSurplusDeficit(puzzle: KakuroPuzzle, state: inout State) -> TechniqueApplication? {
        for run in puzzle.runs {
            let open = openCells(in: run, state: state)
            guard open.count >= 2 else { continue }
            let used = usedDigits(in: run, state: state)
            let rest = run.sum - DigitSet.sum(used)
            // If every open cell except one has a fully determined crossing-run
            // digit set restricted to a single digit-sum contribution, derive
            // the last cell as run-sum arithmetic.
            var determinedSum = 0
            var undetermined: [GridPosition] = []
            for pos in open {
                let cands = state.candidates[pos] ?? DigitSet.all
                if DigitSet.count(cands) == 1 {
                    determinedSum += DigitSet.digits(cands)[0]
                } else {
                    undetermined.append(pos)
                }
            }
            if undetermined.count == 1, let pos = undetermined.first {
                let digit = rest - determinedSum
                let cands = state.candidates[pos] ?? DigitSet.all
                guard digit >= 1, digit <= 9,
                      !DigitSet.contains(used, digit),
                      DigitSet.contains(cands, digit),
                      DigitSet.count(cands) > 1 else { continue }
                return TechniqueApplication(
                    technique: .surplusDeficit,
                    placements: [Placement(position: pos, digit: digit)],
                    focusCells: run.cells,
                    involvedRuns: [run.id],
                    explanation: ExplanationData(runIDs: [run.id], digits: [digit])
                )
            }
        }
        return nil
    }

    // MARK: - Assignment enumeration for combinationReduction

    /// Backtracking over cells x digits: records which digits each cell can take
    /// in at least one complete assignment of `digits` onto `cells`.
    private static func accumulateAssignments(
        cells: [GridPosition], digits: UInt16, state: State,
        into achievable: inout [GridPosition: UInt16]
    ) {
        guard DigitSet.count(digits) == cells.count else { return }
        var assignment: [Int] = []
        func recurse(_ index: Int, remaining: UInt16) {
            if index == cells.count {
                for (i, pos) in cells.enumerated() {
                    achievable[pos, default: 0] |= DigitSet.mask(assignment[i])
                }
                return
            }
            let cands = state.candidates[cells[index]] ?? DigitSet.all
            for digit in DigitSet.digits(remaining & cands) {
                assignment.append(digit)
                recurse(index + 1, remaining: remaining & ~DigitSet.mask(digit))
                assignment.removeLast()
            }
        }
        recurse(0, remaining: digits)
    }

    /// Loose bounds: k smallest / k largest distinct digits from the union of the
    /// cells' candidate sets. Always a superset of the exact achievable range.
    static func looseSumBounds(_ sets: [UInt16], excluding: UInt16) -> (min: Int?, max: Int?) {
        let union = sets.reduce(UInt16(0)) { $0 | ($1 & ~excluding) }
        let digits = DigitSet.digits(union)
        let k = sets.count
        guard digits.count >= k else { return (nil, nil) }
        let minSum = digits.prefix(k).reduce(0, +)
        let maxSum = digits.suffix(k).reduce(0, +)
        return (minSum, maxSum)
    }

    /// Minimum total of one distinct digit per cell drawn from each cell's candidate
    /// set (greedy lower bound; nil if impossible).
    static func minAchievableSum(_ sets: [UInt16], excluding: UInt16) -> Int? {
        achievableSum(sets.map { $0 & ~excluding }, minimize: true)
    }

    static func maxAchievableSum(_ sets: [UInt16], excluding: UInt16) -> Int? {
        achievableSum(sets.map { $0 & ~excluding }, minimize: false)
    }

    /// Exact min/max sum of a system of distinct representatives via small
    /// backtracking (run lengths are <= 9 so this is cheap).
    private static func achievableSum(_ sets: [UInt16], minimize: Bool) -> Int? {
        // Order cells by fewest candidates to fail fast.
        let order = sets.indices.sorted { DigitSet.count(sets[$0]) < DigitSet.count(sets[$1]) }
        var best: Int? = nil
        var current = 0
        func recurse(_ step: Int, used: UInt16) {
            if step == order.count {
                if let b = best {
                    best = minimize ? min(b, current) : max(b, current)
                } else {
                    best = current
                }
                return
            }
            let set = sets[order[step]] & ~used
            for digit in DigitSet.digits(set) {
                current += digit
                recurse(step + 1, used: used | DigitSet.mask(digit))
                current -= digit
            }
        }
        recurse(0, used: 0)
        return best
    }
}
