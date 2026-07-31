import Foundation
import Testing
@testable import Kakuro

@Suite struct SolverTests {

    @Test func solvesTinyUniquePuzzle() {
        let puzzle = Fixtures.tiny2x2Unique
        let result = BacktrackingSolver.countSolutions(puzzle, limit: 3)
        #expect(result.count == 1)
        #expect(result.solutions.first == Fixtures.assignment(of: puzzle))
    }

    @Test func detectsAmbiguity() {
        let result = BacktrackingSolver.countSolutions(Fixtures.tiny2x2Ambiguous, limit: 2)
        #expect(result.count == 2)
    }

    @Test func solvesSmall4x4Uniquely() {
        let puzzle = Fixtures.small4x4
        let result = BacktrackingSolver.countSolutions(puzzle, limit: 3)
        #expect(result.count == 1)
        #expect(result.solutions.first == Fixtures.assignment(of: puzzle))
    }

    @Test func findsSeedAmongMultipleSolutions() {
        let puzzle = Fixtures.medium5x5Ambiguous
        let result = BacktrackingSolver.countSolutions(puzzle, limit: 10)
        #expect(result.count >= 2)
        #expect(result.solutions.contains(Fixtures.assignment(of: puzzle)))
    }

    @Test func limitStopsEarly() {
        let result = BacktrackingSolver.countSolutions(Fixtures.tiny2x2Ambiguous, limit: 1)
        #expect(result.count == 1)
    }

    @Test func builderLayoutValidation() {
        #expect(KakuroBuilder.isValidLayout([
            [nil, nil, nil],
            [nil, 1, 2],
            [nil, 3, 5],
        ]))
        // Orphan single white cell in a column: invalid.
        #expect(!KakuroBuilder.isValidLayout([
            [nil, nil, nil],
            [nil, 1, 2],
            [nil, nil, nil],
        ]))
        // Duplicate digit within a run: invalid.
        #expect(!KakuroBuilder.isValidLayout([
            [nil, nil, nil],
            [nil, 1, 1],
            [nil, 3, 5],
        ]))
    }

    @Test func puzzleCodableRoundTrip() throws {
        let puzzle = Fixtures.small4x4
        let data = try JSONEncoder().encode(puzzle)
        let decoded = try JSONDecoder().decode(KakuroPuzzle.self, from: data)
        #expect(decoded == puzzle)
        #expect(decoded.runIndex == puzzle.runIndex)
    }

    @Test func moveApplyAndUndo() {
        var board = BoardState()
        let pos = GridPosition(row: 1, col: 1)
        let move = Move.setEntry(pos, old: nil, new: 5)
        let inverse = move.apply(to: &board)
        #expect(board.entry(at: pos) == 5)
        inverse.apply(to: &board)
        #expect(board.entry(at: pos) == nil)

        let batch = Move.batch([
            .setEntry(pos, old: nil, new: 3),
            .setNotes(GridPosition(row: 1, col: 2), old: [], new: [1, 2]),
        ])
        let batchInverse = batch.apply(to: &board)
        #expect(board.entry(at: pos) == 3)
        #expect(board.notes(at: GridPosition(row: 1, col: 2)) == [1, 2])
        batchInverse.apply(to: &board)
        #expect(board == BoardState())
    }
}
