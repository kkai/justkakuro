import Foundation
import Testing
@testable import Kakuro

@Suite struct TutorialFixtureTests {

    /// Derived from `bakedTechniques` rather than a hardcoded board list, so a
    /// fifth lesson cannot be added without inheriting this proof.
    @MainActor
    @Test func allTutorialBoardsAreUniqueAndLogicallySolvable() async {
        for technique in TutorialPuzzles.bakedTechniques {
            let lesson = await TutorialPuzzles.lesson(for: technique)
            let uniqueness = BacktrackingSolver.countSolutions(lesson.puzzle, limit: 2)
            #expect(uniqueness.count == 1, "\(lesson.id) board is not unique")
            #expect(LogicalSolver.solve(lesson.puzzle).solved,
                    "\(lesson.id) board is not logically solvable")
        }
    }

    @MainActor
    @Test func scriptedStepsMatchTheirBoards() async {
        // Every requireEntry step's digit must be the actual solution digit.
        for technique in TutorialPuzzles.bakedTechniques {
            let lesson = await TutorialPuzzles.lesson(for: technique)
            for step in lesson.steps {
                switch step {
                case .requireEntry(_, let pos, let digit):
                    #expect(lesson.puzzle.solution(at: pos) == digit,
                            "\(lesson.id): scripted entry \(digit) at \(pos) is wrong")
                case .requireNote(_, let pos, let digits):
                    // Notes must include the solution digit.
                    #expect(digits.contains(lesson.puzzle.solution(at: pos)!),
                            "\(lesson.id): scripted note at \(pos) omits the solution")
                default:
                    break
                }
            }
            // Each lesson ends with a celebration.
            if case .celebrate = lesson.steps.last! {} else {
                Issue.record("\(lesson.id): missing celebrate step")
            }
        }
    }

    @Test func drillPuzzlesExerciseTheirTechnique() {
        // The basics must fire in their drills; deeper techniques are
        // best-effort (drillPuzzle falls back if the seed search fails).
        for technique in [Technique.magicBlock, .crossReference] {
            let drill = PracticeDrills.drillPuzzle(for: technique)
            #expect(drill.techniqueProfile[technique, default: 0] > 0,
                    "\(technique) drill never uses it")
            #expect(BacktrackingSolver.countSolutions(drill.puzzle, limit: 2).count == 1)
        }
    }

    /// The regression that made lesson 2 slow: `duplicateInRun` had no baked
    /// lesson, so it fell through to `PracticeDrills.drillPuzzle` — up to 25
    /// serial generator runs. The early curriculum must never generate.
    @MainActor
    @Test func earlyLessonsAreBakedNotGenerated() {
        for technique in TutorialPuzzles.bakedTechniques {
            #expect(TutorialPuzzles.bakedLesson(for: technique) != nil,
                    "\(technique.map { "\($0)" } ?? "rules") lost its hand-authored lesson")
        }
    }

    /// Catches a generator sneaking back into a baked path. The gap between
    /// baked (instant) and generated (seconds) is ~100x, so the ceiling is
    /// deliberately loose — a debug simulator runs ~5x slower than native.
    @MainActor
    @Test func bakedLessonsLoadPromptly() async {
        for technique in TutorialPuzzles.bakedTechniques {
            let start = ContinuousClock.now
            _ = await TutorialPuzzles.lesson(for: technique)
            #expect(start.duration(to: .now) < .seconds(1),
                    "\(technique.map { "\($0)" } ?? "rules") lesson took too long to build")
        }
    }

    /// The other half of the lesson-2 bug: the board was a medium-band drill
    /// needing techniques the curriculum had not taught yet. After the scripted
    /// entries, the exam must stay inside what lesson 2 has covered — and the
    /// technique being taught must actually be the one that opens it.
    @MainActor
    @Test func noRepeatExamStaysInsideTheCurriculum() async {
        let lesson = await TutorialPuzzles.lesson(for: .duplicateInRun)
        var board = BoardState()
        for step in lesson.steps {
            if case .requireEntry(_, let pos, let digit) = step { board.entries[pos] = digit }
        }
        var state = LogicalSolver.State(puzzle: lesson.puzzle, board: board)
        var tail: [Technique] = []
        while let step = LogicalSolver.nextStep(puzzle: lesson.puzzle, state: &state, apply: true),
              tail.count < 64 {
            tail.append(step.technique)
            if state.candidates.isEmpty { break }
        }
        #expect(tail.contains(.duplicateInRun), "the No Repeats exam never needs No Repeats")
        #expect(tail.allSatisfy { $0 <= .nakedSingle },
                "exam needs \(tail.filter { $0 > .nakedSingle }) — past what lesson 2 has taught")
        #expect(lesson.puzzle.whitePositions.allSatisfy { state.entries[$0] != nil },
                "the exam tail does not solve")
    }

    @MainActor
    @Test(arguments: TutorialPuzzles.bakedTechniques)
    func tutorialEngineWalksBakedLesson(_ technique: Technique?) async {
        let engine = TutorialEngine(lesson: await TutorialPuzzles.lesson(for: technique))
        var safety = 0
        while !engine.finished, safety < 100 {
            safety += 1
            if engine.showsNextButton {
                engine.next()
            } else if case .requireEntry(_, let pos, let digit) = engine.currentStep {
                engine.handleTap(pos)
                engine.handleDigit(digit)
            } else if case .requireNote(_, let pos, let digits) = engine.currentStep {
                engine.handleTap(pos)
                for digit in digits { engine.handleDigit(digit) }
            } else if case .solveFreely = engine.currentStep {
                for pos in engine.game.puzzle.whitePositions
                where engine.game.board.entry(at: pos) == nil {
                    engine.handleTap(pos)
                    engine.handleDigit(engine.game.puzzle.solution(at: pos)!)
                }
            } else {
                break
            }
        }
        #expect(engine.finished,
                "\(engine.lesson.id) did not complete (stuck at step \(engine.stepIndex))")
    }
}
