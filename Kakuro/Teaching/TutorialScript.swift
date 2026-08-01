import Foundation
import Observation

/// One step of a scripted lesson.
enum TutorialStep: Equatable {
    /// Show a message; advances with the Next button.
    case say(String)
    /// Show a message while highlighting cells.
    case sayHighlighting(String, [GridPosition])
    /// Lock input until the player places `digit` at `position`.
    case requireEntry(String, GridPosition, Int)
    /// Lock input until the player's notes at `position` equal `digits`.
    case requireNote(String, GridPosition, Set<Int>)
    /// Free play until the puzzle is solved (the lesson's exam).
    case solveFreely(String)
    /// Completion beat.
    case celebrate(String)
}

struct TutorialLesson: Identifiable {
    let id: String
    /// nil for Lesson 0 (the rules); otherwise the technique taught.
    let technique: Technique?
    let title: String
    let summary: String
    let puzzle: KakuroPuzzle
    let steps: [TutorialStep]
}

/// Drives a lesson: exposes the current step, filters game input, advances
/// when step conditions are met.
@Observable @MainActor
final class TutorialEngine {
    let lesson: TutorialLesson
    let game: KakuroGame

    private(set) var stepIndex = 0
    private(set) var finished = false
    /// Set briefly when the player taps something the step doesn't allow.
    private(set) var wiggle = false

    init(lesson: TutorialLesson) {
        self.lesson = lesson
        let logical = LogicalSolver.solve(lesson.puzzle)
        let generated = GeneratedPuzzle(
            puzzle: lesson.puzzle,
            difficulty: .easy,
            techniqueProfile: logical.histogram
        )
        self.game = KakuroGame(puzzle: generated)
    }

    var currentStep: TutorialStep? {
        stepIndex < lesson.steps.count ? lesson.steps[stepIndex] : nil
    }

    var message: String {
        switch currentStep {
        case .say(let text), .sayHighlighting(let text, _),
             .requireEntry(let text, _, _), .requireNote(let text, _, _),
             .solveFreely(let text), .celebrate(let text):
            return text
        case nil:
            return ""
        }
    }

    var highlightedCells: Set<GridPosition> {
        switch currentStep {
        case .sayHighlighting(_, let cells):
            Set(cells)
        case .requireEntry(_, let pos, _), .requireNote(_, let pos, _):
            [pos]
        default:
            []
        }
    }

    /// Steps that advance via the Next button (no player action needed).
    var showsNextButton: Bool {
        switch currentStep {
        case .say, .sayHighlighting, .celebrate: true
        default: false
        }
    }

    func next() {
        guard showsNextButton else { return }
        if case .celebrate = currentStep {
            finished = true
        }
        advance()
    }

    // MARK: - Filtered input from the board/pad

    func handleTap(_ pos: GridPosition) {
        switch currentStep {
        case .requireEntry(_, let target, _), .requireNote(_, let target, _):
            if pos == target {
                game.tap(pos)
            } else {
                reject()
            }
        case .solveFreely:
            game.tap(pos)
        default:
            reject()
        }
    }

    func handleDigit(_ digit: Int) {
        switch currentStep {
        case .requireEntry(_, let target, let expected):
            guard game.selected == target else { reject(); return }
            if digit == expected, !game.notesMode {
                game.enter(digit)
                Haptics.tap()
                advance()
            } else {
                reject()
            }
        case .requireNote(_, let target, let expected):
            guard game.selected == target, game.notesMode else { reject(); return }
            game.enter(digit)
            if game.board.notes(at: target) == expected {
                Haptics.tap()
                advance()
            }
        case .solveFreely:
            game.enter(digit)
            if game.phase == .won {
                advance()
            }
        default:
            reject()
        }
    }

    private func advance() {
        stepIndex += 1
        // Auto-prime selection/notes mode for requirement steps.
        switch currentStep {
        case .requireEntry(_, let pos, _):
            game.notesMode = false
            game.selected = pos
        case .requireNote(_, let pos, _):
            game.notesMode = true
            game.selected = pos
        case .solveFreely:
            // A preceding requireNote step leaves notes mode on. Carrying it into
            // the exam turns every digit the player enters into a note, so the
            // board can never reach .won — Cross Reference was uncompletable.
            game.notesMode = false
        default:
            break
        }
    }

    private func reject() {
        Haptics.error()
        wiggle = true
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            wiggle = false
        }
    }
}
