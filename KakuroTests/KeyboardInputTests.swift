import Foundation
import SwiftUI
import Testing
@testable import Kakuro

/// The hardware-keyboard path. `PuzzleKeyCommand.from` takes a `KeyEquivalent`
/// rather than a `KeyPress` precisely so it can be exercised here.
@MainActor
@Suite struct KeyboardInputTests {

    private func makeGame(_ puzzle: KakuroPuzzle = Fixtures.small4x4) -> KakuroGame {
        KakuroGame(puzzle: GeneratedPuzzle(
            puzzle: puzzle, difficulty: .easy,
            techniqueProfile: LogicalSolver.solve(puzzle).histogram))
    }

    private func command(_ key: KeyEquivalent,
                         _ modifiers: EventModifiers = []) -> PuzzleKeyCommand? {
        PuzzleKeyCommand.from(key: key, modifiers: modifiers)
    }

    // MARK: - Key mapping

    @Test func theNumberRowEntersDigits() {
        for digit in 1...9 {
            let key = KeyEquivalent(Character("\(digit)"))
            #expect(command(key) == .digit(digit))
        }
    }

    /// 0 is not a Kakuro digit, so it is free to mean "empty this cell" without
    /// taking the hand off the number row.
    @Test func zeroAndBackspaceErase() {
        #expect(command("0") == .erase)
        #expect(command(.delete) == .erase)
        #expect(command(.deleteForward) == .erase)
    }

    /// SwiftUI is inconsistent with itself here: `KeyEquivalent.delete` is
    /// U+0008, but pressing Backspace delivers a `KeyPress` whose key is U+007F.
    /// Matching only the named constant compiles, reads correctly, and does
    /// nothing when the key is pressed, which is exactly what the first Mac
    /// build did.
    @Test func backspaceErasesWhicheverCharacterArrives() {
        #expect(KeyEquivalent.delete.character == "\u{08}",
                "if SwiftUI has fixed this, simplify the erase case")
        #expect(command(KeyEquivalent("\u{7F}")) == .erase,
                "the character the Backspace key actually delivers")
        #expect(command(KeyEquivalent("\u{08}")) == .erase)
    }

    @Test func arrowsMoveAndEscapeDeselects() {
        #expect(command(.upArrow) == .move(.up))
        #expect(command(.downArrow) == .move(.down))
        #expect(command(.leftArrow) == .move(.left))
        #expect(command(.rightArrow) == .move(.right))
        #expect(command(.escape) == .deselect)
    }

    @Test func nTogglesNotesInEitherCase() {
        #expect(command("n") == .toggleNotes)
        #expect(command("N", .shift) == .toggleNotes)
    }

    /// The modifier check has to be real, or a bare `z` would undo and typing
    /// would be unpredictable.
    @Test func undoNeedsCommand() {
        #expect(command("z", .command) == .undo)
        #expect(command("z") == nil)
    }

    /// Shortcuts belonging to the system or the menu bar must pass through
    /// rather than being swallowed by the board.
    @Test func modifiedKeysAreLeftAlone() {
        #expect(command("1", .command) == nil)
        #expect(command("q", .command) == nil)
        #expect(command("n", .control) == nil)
        #expect(command("5", .option) == nil)
    }

    @Test func unmappedKeysDoNothing() {
        for key: KeyEquivalent in ["a", "!", .tab, .return, .space] {
            #expect(command(key) == nil, "\(key.character) should not be bound")
        }
    }

    // MARK: - Selection movement

    @Test func movingFromNothingSelectedPicksTheFirstCell() {
        let game = makeGame()
        #expect(game.selected == nil)
        game.moveSelection(.right)
        #expect(game.selected == game.puzzle.whitePositions.min())
    }

    /// Black cells are stepped over, not stopped at, so arrowing off the end of
    /// a run lands in the next one.
    @Test func movementSkipsBlackCellsAndOnlyLandsOnWhite() {
        let game = makeGame()
        let start = game.puzzle.whitePositions.min()!
        game.selected = start
        for direction in SelectionDirection.allCases {
            game.selected = start
            game.moveSelection(direction)
            let landed = game.selected!
            #expect(game.puzzle.cells[landed.row][landed.col].isWhite,
                    "moved \(direction) onto a black cell at \(landed)")
        }
    }

    /// At the edge the selection stays put. Deselecting there would lose the
    /// player's place in the middle of typing.
    @Test func movementStopsAtTheEdgeWithoutDeselecting() {
        let game = makeGame()
        let first = game.puzzle.whitePositions.min()!
        game.selected = first
        // Walk left until it stops moving, then push once more.
        var previous: GridPosition?
        while game.selected != previous {
            previous = game.selected
            game.moveSelection(.left)
        }
        #expect(game.selected != nil, "ran off the left edge and lost the selection")
        game.moveSelection(.up)
        #expect(game.selected != nil, "ran off the top edge and lost the selection")
    }

    @Test func movementDoesNothingWhilePaused() {
        let game = makeGame()
        let start = game.puzzle.whitePositions.min()!
        game.selected = start
        game.pause()
        game.moveSelection(.right)
        #expect(game.selected == start, "a paused board should not accept movement")
    }

    // MARK: - Command routing

    @Test func digitsGoThroughTheSameEntryPathAsThePad() {
        let game = makeGame()
        let pos = game.puzzle.whitePositions.min()!
        game.selected = pos
        game.handle(.digit(3))
        #expect(game.board.entries[pos] == 3)
        game.handle(.erase)
        #expect(game.board.entries[pos] == nil)
    }

    @Test func notesModeRoutesDigitsToNotes() {
        let game = makeGame()
        let pos = game.puzzle.whitePositions.min()!
        game.selected = pos
        game.handle(.toggleNotes)
        #expect(game.notesMode)
        game.handle(.digit(4))
        #expect(game.board.entries[pos] == nil, "notes mode must not place an entry")
        #expect(game.board.notes(at: pos).contains(4))
    }

    @Test func undoThroughTheKeyboardUnwindsAnEntry() {
        let game = makeGame()
        let pos = game.puzzle.whitePositions.min()!
        game.selected = pos
        game.handle(.digit(2))
        #expect(game.board.entries[pos] == 2)
        game.handle(.undo)
        #expect(game.board.entries[pos] == nil)
    }

    @Test func escapeClearsTheSelection() {
        let game = makeGame()
        game.selected = game.puzzle.whitePositions.min()
        game.handle(.deselect)
        #expect(game.selected == nil)
    }
}
