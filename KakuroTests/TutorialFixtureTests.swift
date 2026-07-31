import Foundation
import Testing
@testable import Kakuro

@Suite struct TutorialFixtureTests {

    @Test func allTutorialBoardsAreUniqueAndLogicallySolvable() {
        for puzzle in [TutorialPuzzles.rulesBoard, TutorialPuzzles.magicBoard,
                       TutorialPuzzles.crossBoard] {
            let uniqueness = BacktrackingSolver.countSolutions(puzzle, limit: 2)
            #expect(uniqueness.count == 1)
            #expect(LogicalSolver.solve(puzzle).solved)
        }
    }

    @MainActor
    @Test func scriptedStepsMatchTheirBoards() async {
        // Every requireEntry step's digit must be the actual solution digit.
        for technique in [nil, Technique.magicBlock, Technique.crossReference] {
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

    @MainActor
    @Test func tutorialEngineWalksRulesLesson() async {
        let engine = TutorialEngine(lesson: await TutorialPuzzles.lesson(for: nil))
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
        #expect(engine.finished, "rules lesson did not complete (stuck at step \(engine.stepIndex))")
    }
}
