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
    let handle: (PuzzleKeyCommand) -> Void
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
        }
        .padding(40)
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
