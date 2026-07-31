import Foundation
import Testing
@testable import Kakuro

@Suite struct GenerationTests {

    @Test func generatedSmallPuzzlesAreValidUniqueAndSolvable() {
        for seed: UInt64 in 1...30 {
            let generated = KakuroGenerator.generate(
                .init(size: .small, difficulty: .easy, seed: seed))
            assertShippable(generated, size: .small, seed: seed)
        }
    }

    @Test func generatedMediumPuzzlesAreValidUniqueAndSolvable() {
        for seed: UInt64 in 1...10 {
            let generated = KakuroGenerator.generate(
                .init(size: .medium, difficulty: .medium, seed: seed))
            assertShippable(generated, size: .medium, seed: seed)
        }
    }

    @Test func generatedLargePuzzlesAreValidUniqueAndSolvable() {
        for seed: UInt64 in 1...5 {
            let generated = KakuroGenerator.generate(
                .init(size: .large, difficulty: .hard, seed: seed))
            assertShippable(generated, size: .large, seed: seed)
        }
    }

    @Test func generationIsDeterministicPerSeed() {
        let a = KakuroGenerator.generate(.init(size: .small, difficulty: .easy, seed: 42))
        let b = KakuroGenerator.generate(.init(size: .small, difficulty: .easy, seed: 42))
        #expect(a == b)
    }

    @Test func easyRequestsProduceEasyPuzzlesMostly() {
        var matches = 0
        let total = 20
        for seed: UInt64 in 100..<UInt64(100 + total) {
            let generated = KakuroGenerator.generate(
                .init(size: .small, difficulty: .easy, seed: seed))
            if generated.difficulty == .easy { matches += 1 }
        }
        // Band matching is best-effort with a budget; most requests must hit.
        #expect(matches >= total * 6 / 10, "only \(matches)/\(total) easy requests matched")
    }

    /// The fallback ships hand-verified grids rather than searching, so the
    /// guarantee `generate` makes — unique and fully solvable by logic, which is
    /// what the hint engine depends on — has to hold for them too.
    @Test func bakedFallbacksAreUniqueAndSolvable() {
        for size in BoardSize.allCases {
            let grids = KakuroGenerator.bakedSolutions(for: size)
            #expect(!grids.isEmpty, "no baked fallback for \(size)")
            for (index, grid) in grids.enumerated() {
                #expect(KakuroBuilder.isValidLayout(grid), "baked \(size) #\(index) has invalid strips")
                let puzzle = KakuroBuilder.puzzle(fromSolutionGrid: grid)
                let counted = BacktrackingSolver.countSolutions(
                    puzzle, limit: 2, nodeLimit: 4_000_000)
                #expect(!counted.aborted, "baked \(size) #\(index) uniqueness check ran out of nodes")
                #expect(counted.count == 1, "baked \(size) #\(index) is not unique")
                #expect(LogicalSolver.solve(puzzle).solved,
                        "baked \(size) #\(index) is not logically solvable")
            }
        }
    }

    /// Every fallback must come back instantly and already graded.
    @Test func fallbackPuzzleReturnsAVerifiedBoard() {
        for size in BoardSize.allCases {
            for seed in 0..<6 {
                var rng = SeededRandomNumberGenerator(seed: UInt64(seed))
                let generated = KakuroGenerator.fallbackPuzzle(size: size, rng: &rng)
                #expect(generated.puzzle.rows == size.dimension)
                #expect(LogicalSolver.solve(generated.puzzle).solved,
                        "fallback \(size) seed \(seed) not logically solvable")
            }
        }
    }

    @Test func topologiesAreSymmetricAndValid() {
        var rng = SeededRandomNumberGenerator(seed: 99)
        for size in BoardSize.allCases {
            var made = 0
            for _ in 0..<40 {
                guard let mask = KakuroGenerator.makeTopology(size: size, rng: &rng) else { continue }
                made += 1
                let d = mask.dimension
                for pos in mask.white {
                    let twin = GridPosition(row: d - pos.row, col: d - pos.col)
                    #expect(mask.white.contains(twin), "topology not 180-degree symmetric")
                }
            }
            #expect(made > 0, "no valid topology produced for \(size)")
        }
    }

    private func assertShippable(_ generated: GeneratedPuzzle, size: BoardSize, seed: UInt64) {
        let puzzle = generated.puzzle
        #expect(puzzle.rows == size.dimension, "seed \(seed)")
        // Structural validity.
        for run in puzzle.runs {
            #expect((2...9).contains(run.length), "seed \(seed): run length \(run.length)")
            #expect(SumCombinations.sumRange(length: run.length).contains(run.sum),
                    "seed \(seed): impossible sum")
        }
        // Every white cell is covered both ways or at least one way with legal runs.
        for pos in puzzle.whitePositions {
            #expect(!puzzle.runs(containing: pos).isEmpty, "seed \(seed): orphan cell")
        }
        // Unique solution matching the embedded one.
        let uniqueness = BacktrackingSolver.countSolutions(puzzle, limit: 2)
        #expect(uniqueness.count == 1, "seed \(seed): not unique")
        #expect(uniqueness.solutions.first == Fixtures.assignment(of: puzzle), "seed \(seed)")
        // Hint guarantee.
        let logical = LogicalSolver.solve(puzzle)
        #expect(logical.solved, "seed \(seed): not logically solvable")
        #expect(generated.techniqueProfile == logical.histogram, "seed \(seed)")
    }
}
