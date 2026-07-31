import Foundation
import Testing
@testable import Kakuro

@Suite struct LogicalSolverTests {

    @Test func solvesTinyPuzzleCompletely() {
        let puzzle = Fixtures.tiny2x2Unique
        let result = LogicalSolver.solve(puzzle)
        #expect(result.solved)
        #expect(!result.trace.isEmpty)
    }

    @Test func solvesSmall4x4Completely() {
        let result = LogicalSolver.solve(Fixtures.small4x4)
        #expect(result.solved)
    }

    @Test func neverPlacesWrongDigitOrRemovesSolutionDigit() {
        for puzzle in [Fixtures.tiny2x2Unique, Fixtures.small4x4] {
            let result = LogicalSolver.solve(puzzle)
            for step in result.trace {
                for placement in step.placements {
                    #expect(puzzle.solution(at: placement.position) == placement.digit,
                            "\(step.technique) placed wrong digit")
                }
                for elimination in step.eliminations {
                    if let solution = puzzle.solution(at: elimination.position) {
                        #expect(!DigitSet.contains(elimination.digits, solution),
                                "\(step.technique) removed the solution digit")
                    }
                }
            }
        }
    }

    @Test func traceIsDeterministic() {
        let a = LogicalSolver.solve(Fixtures.small4x4)
        let b = LogicalSolver.solve(Fixtures.small4x4)
        #expect(a.trace == b.trace)
    }

    @Test func histogramCountsTechniques() {
        let result = LogicalSolver.solve(Fixtures.tiny2x2Unique)
        let histogram = result.histogram
        #expect(histogram.values.reduce(0, +) == result.trace.count)
        #expect(histogram[.magicBlock, default: 0] > 0)
    }

    @Test func stuckOnAmbiguousPuzzle() {
        // An ambiguous puzzle can't be finished by sound logic alone —
        // the solver must stop rather than guess.
        let result = LogicalSolver.solve(Fixtures.tiny2x2Ambiguous)
        #expect(!result.solved)
    }

    @Test func nextStepNilWhenSolved() {
        let puzzle = Fixtures.tiny2x2Unique
        var board = BoardState()
        for pos in puzzle.whitePositions {
            board.entries[pos] = puzzle.solution(at: pos)
        }
        #expect(LogicalSolver.nextStep(puzzle: puzzle, board: board) == nil)
    }
}
