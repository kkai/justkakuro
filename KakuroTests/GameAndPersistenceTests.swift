import Foundation
import Testing
@testable import Kakuro

@MainActor
@Suite struct GameAndPersistenceTests {

    private func makeGame(_ puzzle: KakuroPuzzle = Fixtures.tiny2x2Unique) -> KakuroGame {
        let logical = LogicalSolver.solve(puzzle)
        return KakuroGame(puzzle: GeneratedPuzzle(
            puzzle: puzzle, difficulty: .easy, techniqueProfile: logical.histogram))
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "kakuro-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - Game behavior

    @Test func entryAutoCleansNotesAsOneUndo() {
        let game = makeGame()
        let target = GridPosition(row: 1, col: 1)
        let neighbor = GridPosition(row: 1, col: 2)
        game.tap(neighbor)
        game.notesMode = true
        game.enter(1)
        game.enter(2)
        #expect(game.board.notes(at: neighbor) == [1, 2])
        game.notesMode = false
        game.tap(target)
        game.enter(1)
        // The 1 note in the same run is cleaned with the entry...
        #expect(game.board.notes(at: neighbor) == [2])
        // ...and one undo restores both.
        game.undo()
        #expect(game.board.entry(at: target) == nil)
        #expect(game.board.notes(at: neighbor) == [1, 2])
    }

    @Test func winDetection() {
        let puzzle = Fixtures.tiny2x2Unique
        let game = makeGame(puzzle)
        for pos in puzzle.whitePositions {
            game.tap(pos)
            game.enter(puzzle.solution(at: pos)!)
        }
        #expect(game.phase == .won)
    }

    @Test func autoNotesNeverLeakBeyondBasics() {
        let game = makeGame(Fixtures.small4x4)
        game.fillAutoNotes()
        // Auto-notes must be a superset of the solution digit for every cell:
        // they use only duplicate + magic-block knowledge, never full deduction.
        for pos in game.puzzle.whitePositions {
            let notes = game.board.notes(at: pos)
            #expect(notes.contains(game.puzzle.solution(at: pos)!))
        }
    }

    @Test func impossibleDigitDetection() {
        let game = makeGame()
        // Run 3→ at row 1: digits above 2 are impossible (union of {1,2}).
        #expect(game.isImpossible(digit: 9, at: GridPosition(row: 1, col: 1)))
        #expect(!game.isImpossible(digit: 1, at: GridPosition(row: 1, col: 1)))
    }

    @Test func remainingCombinationsNarrowWithEntries() {
        let game = makeGame(Fixtures.small4x4)
        let run15 = game.puzzle.runs.first { $0.sum == 15 && $0.length == 2 }!
        #expect(game.remainingCombinations(for: run15).count == 2)  // {6,9},{7,8}
        // Place the 6; only {6,9} survives.
        game.tap(run15.cells[0])
        game.enter(6)
        #expect(game.remainingCombinations(for: run15) == [DigitSet.fromDigits([6, 9])])
    }

    // MARK: - Persistence

    @Test func snapshotRoundTripMidGame() throws {
        let game = makeGame()
        game.tap(GridPosition(row: 1, col: 1))
        game.enter(1)
        game.notesMode = true
        game.tap(GridPosition(row: 2, col: 2))
        game.enter(5)

        let store = ProgressStore(userDefaults: isolatedDefaults())
        store.saveGame(game.snapshot)
        let restored = try #require(store.loadSavedGame())
        let resumed = KakuroGame(snapshot: restored)
        #expect(resumed.board == game.board)
        #expect(resumed.puzzle == game.puzzle)
        #expect(resumed.undoStack.count == game.undoStack.count)
        // Undo still works across the round trip.
        resumed.undo()
        #expect(resumed.board.notes(at: GridPosition(row: 2, col: 2)).isEmpty)
    }

    @Test func bestTimesAndStats() {
        let store = ProgressStore(userDefaults: isolatedDefaults())
        #expect(store.bestTime(size: .small, difficulty: .easy) == nil)
        #expect(store.recordSolve(size: .small, difficulty: .easy, time: 100))
        #expect(!store.recordSolve(size: .small, difficulty: .easy, time: 150))
        #expect(store.recordSolve(size: .small, difficulty: .easy, time: 80))
        #expect(store.bestTime(size: .small, difficulty: .easy) == 80)
        #expect(store.stats.puzzlesSolved == 3)
    }

    @Test func persistenceSurvivesReload() {
        let defaults = isolatedDefaults()
        do {
            let store = ProgressStore(userDefaults: defaults)
            store.recordSolve(size: .medium, difficulty: .hard, time: 300)
            store.settings.autoNotes = true
        }
        let reloaded = ProgressStore(userDefaults: defaults)
        #expect(reloaded.bestTime(size: .medium, difficulty: .hard) == 300)
        #expect(reloaded.settings.autoNotes)
        #expect(reloaded.stats.puzzlesSolved == 1)
    }

    /// Resuming has two halves that failed independently: the snapshot must
    /// survive a fresh store (process relaunch), and the in-memory store must
    /// report it immediately so the Continue card appears without a relaunch.
    @Test func savedGameIsVisibleImmediatelyAndAfterRelaunch() throws {
        let defaults = isolatedDefaults()
        let game = makeGame()
        game.tap(GridPosition(row: 1, col: 1))
        game.enter(1)

        let store = ProgressStore(userDefaults: defaults)
        #expect(store.savedGame == nil, "no game should be saved yet")
        store.saveGame(game.snapshot)
        #expect(store.savedGame != nil, "save must be observable right away")

        let relaunched = ProgressStore(userDefaults: defaults)
        let restored = try #require(relaunched.savedGame)
        #expect(KakuroGame(snapshot: restored).board == game.board)

        relaunched.clearSavedGame()
        #expect(relaunched.savedGame == nil)
        #expect(ProgressStore(userDefaults: defaults).savedGame == nil,
                "clearing must survive relaunch too")
    }

    // MARK: - Mastery

    @Test func masteryAdvancesOnMatchingEntries() {
        let puzzle = Fixtures.tiny2x2Unique
        let game = makeGame(puzzle)
        let mastery = MasteryTracker()
        // Solve in solver order, reporting each entry like GameView does.
        // Bounded: a stalled solver must fail the test, not hang it.
        var steps = 0
        while game.phase != .won, steps < 200 {
            steps += 1
            guard let step = LogicalSolver.nextStep(puzzle: puzzle, board: game.board) else { break }
            if let placement = step.placements.first {
                game.tap(placement.position)
                game.enter(placement.digit)
                mastery.recordEntry(position: placement.position, digit: placement.digit, game: game)
            } else {
                let before = game.board
                game.apply(step)
                // Applying an elimination must always change the board,
                // otherwise the hint's Apply button is a no-op.
                #expect(game.board != before, "elimination step made no progress")
                if game.board == before { break }
            }
        }
        #expect(game.phase == .won, "solver-guided play did not finish (steps: \(steps))")
        let total = Technique.allCases.reduce(0) { $0 + mastery.record(for: $1).unaidedUses }
        #expect(total > 0)
    }

    @Test func masteryCreditsEliminationWorkNotJustThePlacement() {
        // A player who places correct digits without writing notes still did the
        // elimination reasoning. Credit must land on that work, not on
        // nakedSingle (the trivial last step that ends every chain).
        for puzzle in [Fixtures.tiny2x2Unique, Fixtures.small4x4] {
            let game = makeGame(puzzle)
            let mastery = MasteryTracker()
            for pos in puzzle.whitePositions {
                let digit = puzzle.solution(at: pos)!
                game.tap(pos)
                game.enter(digit)
                mastery.recordEntry(position: pos, digit: digit, game: game)
            }
            #expect(game.phase == .won)
            let eliminationCredit = [Technique.duplicateInRun, .magicBlock, .crossReference,
                                     .minMaxBounds, .combinationReduction]
                .reduce(0) { $0 + mastery.record(for: $1).unaidedUses }
            #expect(eliminationCredit > 0, "no elimination technique credited for unaided play")
        }
    }

    @Test func masteryStatePersists() {
        let defaults = isolatedDefaults()
        let store = ProgressStore(userDefaults: defaults)
        do {
            let mastery = MasteryTracker(store: store)
            mastery.recordLessonCompleted(.magicBlock)
            for _ in 0..<MasteryTracker.learnedThreshold {
                mastery.recordDrillCompleted(.magicBlock, unaided: true)
            }
            #expect(mastery.state(of: .magicBlock) == .learned)
            // Learning a technique unlocks the next one.
            #expect(mastery.state(of: .crossReference) != .locked)
        }
        let reloaded = MasteryTracker(store: ProgressStore(userDefaults: defaults))
        #expect(reloaded.state(of: .magicBlock) == .learned)
    }
}
