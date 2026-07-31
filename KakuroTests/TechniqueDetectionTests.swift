import Foundation
import Testing
@testable import Kakuro

@Suite struct TechniqueDetectionTests {

    // MARK: - nextStep order (curriculum-first behavior)

    @Test func duplicateInRunFiresFirstAfterEntry() {
        let puzzle = Fixtures.tiny2x2Unique
        var board = BoardState()
        board.entries[GridPosition(row: 1, col: 1)] = 1
        let step = LogicalSolver.nextStep(puzzle: puzzle, board: board)
        #expect(step?.technique == .duplicateInRun)
        // The eliminations remove digit 1 from cells sharing a run with (1,1).
        for elimination in step?.eliminations ?? [] {
            #expect(DigitSet.contains(elimination.digits, 1))
        }
    }

    @Test func magicBlockFiresOnFreshBoard() {
        // tiny2x2Unique has 3→ = {1,2} and other magic runs; nothing is placed,
        // so duplicateInRun can't fire and magicBlock is the first step.
        let step = LogicalSolver.nextStep(puzzle: Fixtures.tiny2x2Unique, board: BoardState())
        #expect(step?.technique == .magicBlock)
        #expect(step?.explanation.combinations.count == 1)
    }

    @Test func crossReferenceFiresWhenNoRunIsMagic() {
        // Sums: across 12 and 14, down 15 and 11 — no unique combinations, so
        // the first useful deduction is the across/down intersection.
        let puzzle = KakuroBuilder.puzzle(fromSolutionGrid: [
            [nil, nil, nil],
            [nil, 9, 3],
            [nil, 6, 8],
        ])
        for run in puzzle.runs {
            #expect(!SumCombinations.isMagic(sum: run.sum, length: run.length))
        }
        let step = LogicalSolver.nextStep(puzzle: puzzle, board: BoardState())
        #expect(step?.technique == .crossReference)
    }

    @Test func minMaxBoundsFiresWhenNotesEncodeCrossKnowledge() {
        // Same puzzle; the player's notes already contain every cross-reference
        // deduction, so the next teachable step is the remaining-sum bound:
        // (1,1) can't be 8 because (1,2) must be 3 and 8+3 ≠ 12.
        let puzzle = KakuroBuilder.puzzle(fromSolutionGrid: [
            [nil, nil, nil],
            [nil, 9, 3],
            [nil, 6, 8],
        ])
        var board = BoardState()
        board.notes[GridPosition(row: 1, col: 1)] = [8, 9]
        board.notes[GridPosition(row: 1, col: 2)] = [3]
        board.notes[GridPosition(row: 2, col: 1)] = [6]
        board.notes[GridPosition(row: 2, col: 2)] = [8]
        let step = LogicalSolver.nextStep(puzzle: puzzle, board: board)
        #expect(step?.technique == .minMaxBounds)
        let elimination = step?.eliminations.first
        #expect(elimination?.position == GridPosition(row: 1, col: 1))
        #expect(elimination.map { DigitSet.digits($0.digits) } == [8])
    }

    @Test func nakedSingleFiresWhenOneCandidateLeft() {
        // All notes are already pinned to the solution digits, so no elimination
        // technique has anything left to do — placing is the next step.
        let puzzle = Fixtures.tiny2x2Unique
        var board = BoardState()
        board.notes[GridPosition(row: 1, col: 1)] = [1]
        board.notes[GridPosition(row: 1, col: 2)] = [2]
        board.notes[GridPosition(row: 2, col: 1)] = [3]
        board.notes[GridPosition(row: 2, col: 2)] = [5]
        let step = LogicalSolver.nextStep(puzzle: puzzle, board: board)
        #expect(step?.technique == .nakedSingle)
        #expect(step?.placements.first == Placement(position: GridPosition(row: 1, col: 1), digit: 1))
    }

    // MARK: - Direct detector behavior

    @Test func hiddenSingleDetector() {
        // Row 2 of small4x4 is 24→ = {7,8,9}. If 9 only fits one open cell,
        // it must go there.
        let puzzle = Fixtures.small4x4
        var state = LogicalSolver.State(puzzle: puzzle)
        state.candidates[GridPosition(row: 2, col: 1)] = DigitSet.fromDigits([7, 8])
        state.candidates[GridPosition(row: 2, col: 2)] = DigitSet.fromDigits([8, 9])
        state.candidates[GridPosition(row: 2, col: 3)] = DigitSet.fromDigits([7, 8])
        let step = LogicalSolver.detectHiddenSingle(puzzle: puzzle, state: &state)
        #expect(step?.technique == .hiddenSingle)
        if let placement = step?.placements.first {
            #expect(puzzle.solution(at: placement.position) == placement.digit)
        } else {
            Issue.record("expected a placement")
        }
    }

    @Test func combinationReductionDetector() {
        // 2-cell run summing 12: combinations {3,9},{4,8},{5,7}. With candidates
        // A={3,4} and B={7,8}, only {4,8} is assignable, so 3 and 7 are pruned.
        let puzzle = KakuroBuilder.puzzle(fromSolutionGrid: [
            [nil, nil, nil],
            [nil, 4, 8],
            [nil, 9, 3],
        ])
        var state = LogicalSolver.State(puzzle: puzzle)
        state.candidates[GridPosition(row: 1, col: 1)] = DigitSet.fromDigits([3, 4])
        state.candidates[GridPosition(row: 1, col: 2)] = DigitSet.fromDigits([7, 8])
        let step = LogicalSolver.detectCombinationReduction(puzzle: puzzle, state: &state)
        #expect(step?.technique == .combinationReduction)
        let removed = Dictionary(uniqueKeysWithValues: (step?.eliminations ?? []).map {
            ($0.position, DigitSet.digits($0.digits))
        })
        #expect(removed[GridPosition(row: 1, col: 1)] == [3])
        #expect(removed[GridPosition(row: 1, col: 2)] == [7])
    }

    @Test func surplusDeficitDetector() {
        // Row 2 of small4x4 (24→): if two cells are pinned to single candidates
        // (7 and 8), the third is forced to 24 - 15 = 9 by sum arithmetic.
        let puzzle = Fixtures.small4x4
        var state = LogicalSolver.State(puzzle: puzzle)
        state.candidates[GridPosition(row: 2, col: 1)] = DigitSet.fromDigits([7])
        state.candidates[GridPosition(row: 2, col: 3)] = DigitSet.fromDigits([8])
        state.candidates[GridPosition(row: 2, col: 2)] = DigitSet.fromDigits([5, 9])
        let step = LogicalSolver.detectSurplusDeficit(puzzle: puzzle, state: &state)
        #expect(step?.technique == .surplusDeficit)
        #expect(step?.placements.first == Placement(position: GridPosition(row: 2, col: 2), digit: 9))
    }

    @Test func notesAreRespected() {
        // A player note that already encodes a deduction must not be re-taught:
        // seeded candidates start from the notes, not from scratch.
        let puzzle = Fixtures.tiny2x2Unique
        var board = BoardState()
        board.notes[GridPosition(row: 1, col: 1)] = [1, 2]
        board.notes[GridPosition(row: 1, col: 2)] = [1, 2]
        let step = LogicalSolver.nextStep(puzzle: puzzle, board: board)
        // The 3→ magic block is already in the notes; the next teachable thing
        // must concern other cells or a different technique.
        if let step, step.technique == .magicBlock {
            let noteCells: Set<GridPosition> = [GridPosition(row: 1, col: 1), GridPosition(row: 1, col: 2)]
            let targets = Set(step.eliminations.map(\.position))
            #expect(!targets.isSubset(of: noteCells) || targets.isEmpty
                    || !step.eliminations.allSatisfy { noteCells.contains($0.position) })
        }
        #expect(step != nil)
    }
}
