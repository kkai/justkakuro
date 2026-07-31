import Foundation
import Testing
@testable import Kakuro

@MainActor
@Suite struct HintEngineTests {

    private func makeGame(_ puzzle: KakuroPuzzle) -> KakuroGame {
        let logical = LogicalSolver.solve(puzzle)
        return KakuroGame(puzzle: GeneratedPuzzle(
            puzzle: puzzle, difficulty: .easy, techniqueProfile: logical.histogram))
    }

    @Test func hintStartsAtNudgeAndEscalates() {
        let game = makeGame(Fixtures.tiny2x2Unique)
        let engine = HintEngine()
        let mastery = MasteryTracker()

        let nudge = engine.hint(for: game, mastery: mastery)
        #expect(nudge.level == .nudge)
        #expect(nudge.highlightCells.isEmpty)
        #expect(!nudge.isErrorHint)

        let technique = engine.escalate(nudge, for: game, mastery: mastery)
        #expect(technique.level == .technique)

        let highlight = engine.escalate(technique, for: game, mastery: mastery)
        #expect(highlight.level == .highlight)
        #expect(!highlight.highlightCells.isEmpty)

        let resolution = engine.escalate(highlight, for: game, mastery: mastery)
        #expect(resolution.level == .resolution)
        // Resolution doesn't escalate further.
        #expect(engine.escalate(resolution, for: game, mastery: mastery).level == .resolution)
    }

    @Test func errorsTakePriorityOverTeaching() {
        let game = makeGame(Fixtures.tiny2x2Unique)
        // Place a wrong digit: (1,1) should be 1.
        game.tap(GridPosition(row: 1, col: 1))
        game.enter(2)
        let hint = HintEngine().hint(for: game, mastery: MasteryTracker())
        #expect(hint.isErrorHint)
    }

    @Test func applyingResolutionIsOneUndoableMove() {
        let game = makeGame(Fixtures.tiny2x2Unique)
        let engine = HintEngine()
        let mastery = MasteryTracker()
        var hint = engine.hint(for: game, mastery: mastery)
        while hint.level < .resolution {
            hint = engine.escalate(hint, for: game, mastery: mastery)
        }
        let undoDepthBefore = game.undoStack.count
        let boardBefore = game.board
        game.apply(hint.application)
        #expect(game.board != boardBefore)
        #expect(game.undoStack.count == undoDepthBefore + 1)
        game.undo()
        #expect(game.board == boardBefore)
    }

    @Test func hintsReportToMastery() {
        let game = makeGame(Fixtures.tiny2x2Unique)
        let engine = HintEngine()
        let mastery = MasteryTracker()
        var hint = engine.hint(for: game, mastery: mastery)
        hint = engine.escalate(hint, for: game, mastery: mastery)
        hint = engine.escalate(hint, for: game, mastery: mastery)
        let record = mastery.record(for: hint.application.technique)
        #expect(record.hintedUses > 0)
    }

    @Test func solvedBoardGivesGentleHint() {
        let puzzle = Fixtures.tiny2x2Unique
        let game = makeGame(puzzle)
        for pos in puzzle.whitePositions {
            game.tap(pos)
            game.enter(puzzle.solution(at: pos)!)
        }
        // Game is won; hint should not crash and not flag errors.
        let hint = HintEngine().hint(for: game, mastery: MasteryTracker())
        #expect(!hint.isErrorHint)
    }
    /// The player-facing promise of the hint button: keep asking, keep applying,
    /// and the board finishes. A step whose Apply is a no-op would stall this
    /// loop forever while still looking like the engine is teaching, so assert
    /// progress on every round rather than only at the end.
    @Test func repeatedHintAndApplySolvesAPuzzle() {
        for seed in UInt64(0)..<3 {
            let generated = KakuroGenerator.generate(
                .init(size: .small, difficulty: .easy, seed: seed))
            let game = KakuroGame(puzzle: generated)
            let engine = HintEngine()
            let mastery = MasteryTracker()

            var rounds = 0
            while game.phase != .won {
                rounds += 1
                #expect(rounds < 500, "hint loop did not converge for seed \(seed)")
                if rounds >= 500 { break }

                let before = game.board
                var hint = engine.hint(for: game, mastery: mastery)
                while hint.level < .resolution {
                    hint = engine.escalate(hint, for: game, mastery: mastery)
                }
                game.apply(hint.application)
                #expect(game.board != before,
                        "Apply made no change on round \(rounds), seed \(seed), technique \(hint.application.technique)")
                if game.board == before { break }
            }
            #expect(game.phase == .won, "seed \(seed) never reached a win")
        }
    }

}
