import Foundation

/// Machine solver: counts solutions via backtracking with combination-feasibility
/// pruning. Used only to prove uniqueness during generation — never for hints.
nonisolated struct BacktrackingSolver: Sendable {

    struct Result: Sendable {
        let count: Int
        /// Up to `limit` full solutions found, keyed by position.
        let solutions: [[GridPosition: Int]]
        /// True when the node budget ran out before the search finished; the
        /// count is then a lower bound and the puzzle must be treated as unproven.
        let aborted: Bool
        /// Search nodes expanded — lets callers meter a global work budget.
        let nodesUsed: Int
    }

    /// Counts solutions, stopping at `limit`. `limit: 2` is enough to prove or
    /// disprove uniqueness while exiting ambiguous grids early. `nodeLimit`
    /// bounds worst-case search so generation time stays predictable.
    static func countSolutions(
        _ puzzle: KakuroPuzzle, limit: Int = 2, nodeLimit: Int = 250_000
    ) -> Result {
        var ctx = Context(puzzle: puzzle, limit: limit, nodeLimit: nodeLimit)
        ctx.search()
        return Result(count: ctx.found.count, solutions: ctx.found,
                      aborted: ctx.nodes >= ctx.nodeLimit, nodesUsed: ctx.nodes)
    }

    private struct Context {
        let puzzle: KakuroPuzzle
        let limit: Int
        let nodeLimit: Int
        var nodes = 0
        let positions: [GridPosition]
        var assignment: [GridPosition: Int] = [:]
        /// Digits already used per run id.
        var used: [UInt16]
        /// Sum of digits already placed per run id.
        var placedSum: [Int]
        /// Cells remaining per run id.
        var remaining: [Int]
        var found: [[GridPosition: Int]] = []

        init(puzzle: KakuroPuzzle, limit: Int, nodeLimit: Int) {
            self.puzzle = puzzle
            self.limit = limit
            self.nodeLimit = nodeLimit
            self.positions = puzzle.whitePositions
            self.used = Array(repeating: 0, count: puzzle.runs.count)
            self.placedSum = Array(repeating: 0, count: puzzle.runs.count)
            self.remaining = puzzle.runs.map(\.length)
        }

        mutating func search() {
            guard found.count < limit, nodes < nodeLimit else { return }
            nodes += 1
            // Most-constrained-first: pick the unassigned cell with fewest candidates.
            var best: (pos: GridPosition, candidates: UInt16)? = nil
            for pos in positions where assignment[pos] == nil {
                let cands = candidates(at: pos)
                if cands == 0 { return }  // dead end
                if best == nil || DigitSet.count(cands) < DigitSet.count(best!.candidates) {
                    best = (pos, cands)
                    if DigitSet.count(cands) == 1 { break }
                }
            }
            guard let (pos, cands) = best else {
                found.append(assignment)
                return
            }
            var digit = 1
            while digit <= 9 {
                if cands & (1 << digit) != 0 {
                    place(digit, at: pos)
                    search()
                    unplace(digit, at: pos)
                    if found.count >= limit { return }
                }
                digit += 1
            }
        }

        /// Hot path: allocation-free bit twiddling only.
        func candidates(at pos: GridPosition) -> UInt16 {
            var cands = DigitSet.all
            guard let pair = puzzle.runIndex[pos] else { return 0 }
            for runID in [pair.across, pair.down] {
                guard let runID else { continue }
                let run = puzzle.runs[runID]
                let usedMask = used[runID]
                // Digits must come from a combination consistent with what's placed.
                var feasible: UInt16 = 0
                for combo in SumCombinations.combinations(sum: run.sum, length: run.length)
                where combo & usedMask == usedMask {
                    feasible |= combo
                }
                cands &= feasible & ~usedMask
                // Remaining-sum bound: this cell plus the other open cells must hit the target.
                let rest = run.sum - placedSum[runID]
                let others = remaining[runID] - 1
                if others == 0 {
                    cands = (rest >= 1 && rest <= 9 && DigitSet.contains(cands, rest))
                        ? DigitSet.mask(rest) : 0
                } else {
                    // Loose min/max bound for the open cells excluding this one.
                    let minOthers = others * (others + 1) / 2
                    let maxOthers = others * (19 - others) / 2
                    var bounded: UInt16 = 0
                    var d = 1
                    while d <= 9 {
                        if cands & (1 << d) != 0 {
                            let need = rest - d
                            if need >= minOthers && need <= maxOthers { bounded |= 1 << d }
                        }
                        d += 1
                    }
                    cands = bounded
                }
                if cands == 0 { return 0 }
            }
            return cands
        }

        mutating func place(_ digit: Int, at pos: GridPosition) {
            assignment[pos] = digit
            guard let pair = puzzle.runIndex[pos] else { return }
            for runID in [pair.across, pair.down] {
                guard let runID else { continue }
                used[runID] |= DigitSet.mask(digit)
                placedSum[runID] += digit
                remaining[runID] -= 1
            }
        }

        mutating func unplace(_ digit: Int, at pos: GridPosition) {
            assignment[pos] = nil
            guard let pair = puzzle.runIndex[pos] else { return }
            for runID in [pair.across, pair.down] {
                guard let runID else { continue }
                used[runID] &= ~DigitSet.mask(digit)
                placedSum[runID] -= digit
                remaining[runID] += 1
            }
        }
    }
}
