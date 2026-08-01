import Foundation
import Testing
@testable import Kakuro

/// Every case here pins a defect that shipped because nothing tested it.
@MainActor
@Suite struct StatsCorrectnessTests {

    private func makeGame(_ puzzle: KakuroPuzzle = Fixtures.tiny2x2Unique,
                          requested: Difficulty? = nil) -> KakuroGame {
        let logical = LogicalSolver.solve(puzzle)
        return KakuroGame(
            puzzle: GeneratedPuzzle(puzzle: puzzle, difficulty: .easy,
                                    techniqueProfile: logical.histogram),
            requestedDifficulty: requested)
    }

    private func isolatedDefaults() -> UserDefaults {
        let name = "kakuro-stats-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    // MARK: - Timer

    /// The overnight-background bug: `tick` adds a wall-clock delta, so a paused
    /// game must not accumulate the time the app spent suspended.
    @Test func pausedTimeIsNotCounted() {
        let game = makeGame()
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        game.tick(now: t0)
        game.tick(now: t0.addingTimeInterval(5))
        #expect(abs(game.elapsed - 5) < 0.001)

        game.pause()
        // Eight hours of "backgrounded" wall clock.
        game.tick(now: t0.addingTimeInterval(5 + 8 * 3600))
        #expect(abs(game.elapsed - 5) < 0.001, "paused time leaked into elapsed")

        game.resume()
        let t1 = t0.addingTimeInterval(5 + 8 * 3600)
        game.tick(now: t1)
        game.tick(now: t1.addingTimeInterval(3))
        #expect(abs(game.elapsed - 8) < 0.001, "resume should continue, not restart or jump")
    }

    @Test func elapsedSurvivesASnapshotRoundTrip() {
        let game = makeGame()
        let t0 = Date(timeIntervalSince1970: 2_000_000)
        game.tick(now: t0)
        game.tick(now: t0.addingTimeInterval(42))

        let restored = KakuroGame(snapshot: game.snapshot)
        #expect(abs(restored.elapsed - 42) < 0.001)
    }

    // MARK: - Which column a solve is filed under

    /// `generate` returns the nearest band when its budget runs out, so the
    /// delivered band can differ from the request. Everything else in the app
    /// keys on the request; stats must too, or a best time lands in a column the
    /// player never chose.
    @Test func solvesAreFiledUnderTheRequestedDifficulty() {
        let game = makeGame(requested: .hard)          // delivered band is .easy
        #expect(game.generated.difficulty == .easy)
        #expect(game.difficultyForRecords == .hard)
    }

    @Test func aGameWithNoRecordedRequestFallsBackToTheDeliveredBand() {
        let game = makeGame(requested: nil)
        #expect(game.difficultyForRecords == .easy)
    }

    @Test func requestedDifficultySurvivesResume() {
        let game = makeGame(requested: .hard)
        let restored = KakuroGame(snapshot: game.snapshot)
        #expect(restored.difficultyForRecords == .hard)
    }

    // MARK: - Mastery

    /// Applying a hint is the hint's work. Five of them used to mark a technique
    /// "Learned" for a player who never applied it themselves.
    @Test func appliedHintsDoNotAdvanceUnaidedMastery() {
        let game = makeGame()
        let mastery = MasteryTracker()
        let pos = game.puzzle.whitePositions.min()!
        let digit = game.puzzle.solution(at: pos)!

        game.selected = pos
        game.enter(digit)
        mastery.recordEntry(position: pos, digit: digit, game: game, unaided: false)

        let credited = Technique.allCases.filter { mastery.record(for: $0).unaidedUses > 0 }
        #expect(credited.isEmpty, "hinted placement credited \(credited)")
    }

    /// The same placement, self-directed, must still count — otherwise the fix
    /// above would have silently disabled mastery entirely.
    @Test func unaidedEntriesStillAdvanceMastery() {
        let game = makeGame()
        let mastery = MasteryTracker()
        let pos = game.puzzle.whitePositions.min()!
        let digit = game.puzzle.solution(at: pos)!

        game.selected = pos
        game.enter(digit)
        mastery.recordEntry(position: pos, digit: digit, game: game, unaided: true)

        let credited = Technique.allCases.filter { mastery.record(for: $0).unaidedUses > 0 }
        #expect(!credited.isEmpty, "an unaided correct placement earned no credit")
    }

    /// Place, undo, place again used to earn credit every time round.
    @Test func undoAndReplaceDoesNotFarmMastery() {
        let game = makeGame()
        let mastery = MasteryTracker()
        let pos = game.puzzle.whitePositions.min()!
        let digit = game.puzzle.solution(at: pos)!

        // Mirrors GameView.handleEntriesChange: the cell must claim its one-off
        // credit before the tracker is asked.
        func placeAndRecord() {
            game.selected = pos
            game.enter(digit)
            let firstTime = game.claimMasteryCredit(at: pos)
            mastery.recordEntry(position: pos, digit: digit, game: game, unaided: firstTime)
        }

        placeAndRecord()
        let afterFirst = Technique.allCases.reduce(0) { $0 + mastery.record(for: $1).unaidedUses }

        for _ in 0..<4 {
            game.undo()
            placeAndRecord()
        }
        let afterLoop = Technique.allCases.reduce(0) { $0 + mastery.record(for: $1).unaidedUses }
        #expect(afterLoop == afterFirst,
                "undo/replace farmed \(afterLoop - afterFirst) extra unaided uses")
    }

    // MARK: - Formatting

    @Test func clockRollsOverPastAnHour() {
        #expect(TimeFormatting.clock(0) == "0:00")
        #expect(TimeFormatting.clock(9) == "0:09")
        #expect(TimeFormatting.clock(74) == "1:14")
        // Used to render as "72:14".
        #expect(TimeFormatting.clock(72 * 60 + 14) == "1:12:14")
        #expect(TimeFormatting.clock(3600) == "1:00:00")
    }

    /// The first-run Stats screen used to read "1 solved / 0m played".
    @Test func durationSaysSomethingTrueBelowAMinute() {
        #expect(TimeFormatting.duration(45) == "45s")
        #expect(TimeFormatting.duration(0) == "0s")
        #expect(TimeFormatting.duration(60) == "1m")
        #expect(TimeFormatting.duration(59 * 60) == "59m")
        #expect(TimeFormatting.duration(3 * 3600 + 4 * 60) == "3h 04m")
    }

    // MARK: - Totals

    @Test func recordSolveAccumulatesPlayTimeAndCounts() {
        let store = ProgressStore(userDefaults: isolatedDefaults())
        store.recordSolve(size: .small, difficulty: .easy, time: 100)
        store.recordSolve(size: .small, difficulty: .easy, time: 80)
        store.recordSolve(size: .medium, difficulty: .hard, time: 150)

        #expect(store.stats.puzzlesSolved == 3)
        #expect(abs(store.stats.totalPlayTime - 330) < 0.001)
        #expect(store.bestTime(size: .small, difficulty: .easy) == 80)
        #expect(store.stats.solvedBySize[.small] == 2)
        #expect(store.stats.solvedByDifficulty[.hard] == 1)
    }

    /// Drills and lessons must never inflate the puzzle count. Guarded by test
    /// rather than by grep, so a future `recordSolve` call site is caught.
    @Test func practiceAndTutorialDoNotRecordSolves() throws {
        let sources = ["Kakuro/Teaching/PracticeView.swift",
                       "Kakuro/Teaching/TutorialView.swift",
                       "Kakuro/Teaching/TutorialScript.swift"]
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        for relative in sources {
            let text = try String(contentsOf: root.appending(path: relative), encoding: .utf8)
            #expect(!text.contains("recordSolve"),
                    "\(relative) records a solve; drills and lessons must not count as puzzles")
        }
    }
}
