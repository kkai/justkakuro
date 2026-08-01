import SwiftUI

/// Which way the selection moves.
nonisolated enum SelectionDirection: Sendable, CaseIterable, Hashable {
    case up, down, left, right

    var delta: (row: Int, col: Int) {
        switch self {
        case .up: (-1, 0)
        case .down: (1, 0)
        case .left: (0, -1)
        case .right: (0, 1)
        }
    }
}

/// What a keystroke means inside a puzzle.
///
/// Kept separate from the views, and built from a `KeyEquivalent` rather than a
/// `KeyPress`, because `KeyPress` cannot be constructed outside SwiftUI's own
/// event delivery. A mapping that can only be exercised by pressing keys by hand
/// is a mapping with no tests.
nonisolated enum PuzzleKeyCommand: Equatable, Sendable, Hashable {
    case digit(Int)
    case erase
    case toggleNotes
    case undo
    case deselect
    case move(SelectionDirection)

    static func from(key: KeyEquivalent, modifiers: EventModifiers) -> PuzzleKeyCommand? {
        // Command is the only modifier that carries meaning, and only for undo.
        // Everything else with a modifier belongs to the system or the menu bar,
        // so it is passed through rather than swallowed.
        if modifiers.contains(.command) {
            return key.character == "z" ? .undo : nil
        }
        guard !modifiers.contains(.control), !modifiers.contains(.option) else { return nil }

        switch key.character {
        case "1"..."9":
            return .digit(key.character.wholeNumberValue!)
        // 0 is not a Kakuro digit, so it is free to mean "empty this cell",
        // which is where a hand on the number row already is.
        //
        // Both backspace characters are listed on purpose. `KeyEquivalent.delete`
        // is U+0008, but pressing Backspace delivers a `KeyPress` whose key is
        // U+007F, so matching SwiftUI's own constant alone silently misses the
        // key it names. Measured on macOS 15; the erase key did nothing until
        // U+007F was added. Covered by `backspaceErasesWhicheverCharacterArrives`.
        case "0", "\u{08}", "\u{7F}", KeyEquivalent.deleteForward.character:
            return .erase
        case "n", "N":
            return .toggleNotes
        case KeyEquivalent.escape.character:
            return .deselect
        case KeyEquivalent.upArrow.character:
            return .move(.up)
        case KeyEquivalent.downArrow.character:
            return .move(.down)
        case KeyEquivalent.leftArrow.character:
            return .move(.left)
        case KeyEquivalent.rightArrow.character:
            return .move(.right)
        default:
            return nil
        }
    }
}

/// Routes hardware keys into a puzzle.
///
/// The handler is a closure rather than a `KakuroGame` because the tutorial does
/// not drive its game directly: its digits have to pass through `TutorialEngine`,
/// which is what the lesson script watches. A modifier that took a game would
/// quietly bypass the lesson.
private struct PuzzleKeyboard: ViewModifier {
    let handle: (PuzzleKeyCommand) -> Void

    @FocusState private var focused: Bool

    func body(content: Content) -> some View {
        content
            .focusable()
            // The whole board is one focus target, so the system ring would draw
            // a rectangle around the entire screen.
            .focusEffectDisabled()
            .focused($focused)
            .onAppear { focused = true }
            .onKeyPress(phases: .down) { press in
                guard let command = PuzzleKeyCommand.from(key: press.key,
                                                          modifiers: press.modifiers) else {
                    return .ignored
                }
                handle(command)
                return .handled
            }
    }
}

extension View {
    /// No-op on tvOS, and that is the whole point.
    ///
    /// `PuzzleKeyboard` makes the entire screen one focusable item and disables
    /// the focus effect. On iOS and macOS that is exactly right: it is a shim
    /// for a hardware keyboard and there is a pointer for everything else. On
    /// tvOS the focus engine IS the cursor, so a single screen-sized focus
    /// target leaves the remote with nowhere to go and the board unreachable.
    @ViewBuilder
    func puzzleKeyboard(_ handle: @escaping (PuzzleKeyCommand) -> Void) -> some View {
        #if os(tvOS)
        self
        #else
        modifier(PuzzleKeyboard(handle: handle))
        #endif
    }
}
