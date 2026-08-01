#if os(tvOS)
import SwiftUI

/// tvOS digit entry: the thing that opens when Select is pressed on a cell.
///
/// A television has no touch and no keyboard, so a digit has to be *chosen*. The
/// alternative shapes are worse: a keypad parked beside the board makes every
/// entry a walk across the screen and back, and cycling a cell with repeated
/// Select presses costs nine clicks to reach a 9. A 3x3 grid put where the eye
/// already is keeps it to one short focus move and one click.
///
/// It calls nothing but `PuzzleKeyCommand`, so it shares an entry point with the
/// hardware keyboard rather than inventing a second path into the game.
struct DigitChooser: View {
    /// Notes mode is shown so the player can see which mode they are placing in.
    let notesMode: Bool
    let canErase: Bool
    let paused: Bool
    let handle: (PuzzleKeyCommand) -> Void
    /// Board-level actions that are not digit entry. They live here because the
    /// alternative was a separate control strip on the screen, and focus could
    /// not reliably travel between it and the grid: the remote would go up out
    /// of the board and find nothing, or worse, get in and not get back. One
    /// focusable surface at a time removes the whole class of problem.
    let onHint: () -> Void
    let onAutoNotes: () -> Void
    let onPause: () -> Void
    let close: () -> Void

    @FocusState private var focused: PuzzleKeyCommand?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        VStack(spacing: 20) {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(1...9, id: \.self) { digit in
                    key(.digit(digit)) {
                        Text("\(digit)")
                            .font(Theme.digitFont(size: 56))
                    }
                }
            }
            HStack(spacing: 16) {
                key(.toggleNotes) {
                    Label(notesMode ? "Notes on" : "Notes",
                          systemImage: notesMode ? "pencil.circle.fill" : "pencil.circle")
                        .font(.title3)
                }
                key(.erase) {
                    Label("Erase", systemImage: "delete.left")
                        .font(.title3)
                }
                .disabled(!canErase)
            }
            HStack(spacing: 16) {
                action("Hint", "lightbulb", onHint)
                action("Auto notes", "wand.and.stars", onAutoNotes)
                action(paused ? "Resume" : "Pause", paused ? "play" : "pause", onPause)
            }
        }
        .padding(40)
        // Without a cap the grid takes the full 1920pt and the digits become
        // wide letterbox bars rather than keys.
        .frame(width: 900)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Theme.paper)
                .shadow(color: .black.opacity(0.35), radius: 30, y: 10)
        )
        .onAppear { focused = .digit(1) }
        // The Menu button backs out without placing anything. Without this the
        // only way to close would be to enter a digit you did not want.
        .onExitCommand(perform: close)
    }

    /// A board action rather than a digit. Always closes: none of these are
    /// modes you would fire twice in a row.
    private func action(_ title: String, _ symbol: String,
                        _ perform: @escaping () -> Void) -> some View {
        Button {
            perform()
            close()
        } label: {
            Label(title, systemImage: symbol)
                .font(.title3)
                .foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.surface.opacity(0.6)))
        }
        .buttonStyle(.kakuro)
    }

    private func key(_ command: PuzzleKeyCommand,
                     @ViewBuilder label: () -> some View) -> some View {
        Button {
            handle(command)
            // Notes is a mode, so the chooser stays open for the digit that
            // follows. Everything else has done its job and gets out of the way.
            if command != .toggleNotes { close() }
        } label: {
            label()
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, minHeight: 88)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.surface))
        }
        .buttonStyle(.kakuro)
        .focused($focused, equals: command)
    }
}
#endif
