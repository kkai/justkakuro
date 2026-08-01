import Foundation

/// Drill boards for practicing one technique.
///
/// Most techniques are found by asking the generator for a board whose solve
/// trace uses them, which it can filter for directly while it grades candidates.
///
/// Three cannot be found that way at all. `duplicateInRun`, `hiddenSingle` and
/// `surplusDeficit` appear in **zero** solve traces across every size and
/// difficulty, because the detectors ahead of them in curriculum order always
/// reach the same cells first: a placement already removes the digit from its
/// run-mates' candidates, so the dedicated no-repeat step never has work left,
/// and the cheap eliminations resolve the boards before the arithmetic ones are
/// consulted. Searching for them burns the full budget and then returns a board
/// that does not drill the technique at all. Those three get hand-authored
/// boards instead, verified by `PracticeDrillTests`.
nonisolated enum PracticeDrills {

    /// How many uses of its own technique a searched drill must show.
    static func minimumUses(of technique: Technique) -> Int {
        technique <= .crossReference ? 2 : 1
    }

    /// Techniques whose drills are hand-authored because no search can produce
    /// them. Iterated by the tests, so this list cannot drift from the table.
    static let handAuthored: [Technique] = [.duplicateInRun, .hiddenSingle, .surplusDeficit]

    /// Hand-authored drill boards. Each is machine-verified unique and logically
    /// solvable; each is also shaped so the technique is the natural way in.
    static func bakedGrids(for technique: Technique) -> [[[Int?]]] {
        switch technique {
        case .duplicateInRun:
            // 6 across three cells is {1,2,3} and nothing else, because 2+2+2
            // repeats. 3 down two cells is {1,2} for the same reason. Every
            // deduction here is a no-repeat kill.
            //   .    3↓  10↓ 12↓
            //   6→   1   2   3
            //  19→   2   8   9
            [[[nil, nil, nil, nil],
              [nil, 1, 2, 3],
              [nil, 2, 8, 9]]]

        case .hiddenSingle:
            // 10 across four cells is {1,2,3,4}. Of those four columns only the
            // last can hold a 4: 3 down is {1,2}, 8 down tops out at 3 in the
            // top row, 4 down is {1,3}. The digit the run needs has exactly one
            // place to go.
            //   .    3↓  8↓  4↓  7↓
            //  10→   1   2   3   4
            //  12→   2   6   1   3
            [[[nil, nil, nil, nil, nil],
              [nil, 1, 2, 3, 4],
              [nil, 2, 6, 1, 3]]]

        case .surplusDeficit:
            // Four-cell runs with a wide spread: once three cells are certain
            // the fourth is the clue minus their total, which is faster here
            // than reasoning about candidate sets.
            //   .    3↓  9↓  11↓ 13↓
            //  10→   1   2   3   4
            //  26→   2   7   8   9
            [[[nil, nil, nil, nil, nil],
              [nil, 1, 2, 3, 4],
              [nil, 2, 7, 8, 9]]]

        default:
            []
        }
    }

    /// A drill board for `technique`. Deterministic per `(technique, variant)`.
    static func drillPuzzle(for technique: Technique, variant: UInt64 = 0,
                            control: KakuroGenerator.Control = .none) -> GeneratedPuzzle {
        let grids = bakedGrids(for: technique)
        if !grids.isEmpty {
            let grid = grids[Int(variant % UInt64(grids.count))]
            return graded(KakuroBuilder.puzzle(fromSolutionGrid: grid))
        }

        // One search that filters as it grades, rather than running the whole
        // generator repeatedly and throwing away boards that miss.
        let minUses = minimumUses(of: technique)
        let seed = 0x00D5_1000 &+ UInt64(technique.rawValue) &* 977 &+ variant &* 7919
        return KakuroGenerator.generate(
            .init(size: .small,
                  difficulty: technique >= .combinationReduction ? .hard : .medium,
                  seed: seed,
                  accepts: { ($0[technique] ?? 0) >= minUses }),
            control: control)
    }

    private static func graded(_ puzzle: KakuroPuzzle) -> GeneratedPuzzle {
        let logical = LogicalSolver.solve(puzzle)
        let score = DifficultyRater.score(profile: logical.histogram, solved: logical.solved)
        return GeneratedPuzzle(
            puzzle: puzzle,
            difficulty: DifficultyRater.band(forScore: score, size: .small),
            techniqueProfile: logical.histogram)
    }
}
