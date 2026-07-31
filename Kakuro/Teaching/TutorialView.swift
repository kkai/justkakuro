import SwiftUI

/// Plays one scripted lesson: board on top, coach bubble below, filtered input.
struct TutorialView: View {
    let technique: Technique?
    @Environment(MasteryTracker.self) private var mastery
    @Environment(\.dismiss) private var dismiss

    @State private var engine: TutorialEngine?

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            if let engine {
                lessonBody(engine)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Setting up the lesson…")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .navigationTitle(engine?.lesson.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard engine == nil else { return }
            engine = TutorialEngine(lesson: await TutorialPuzzles.lesson(for: technique))
        }
    }

    private func lessonBody(_ engine: TutorialEngine) -> some View {
        VStack(spacing: 14) {
            BoardView(game: engine.game, highlighted: engine.highlightedCells) { pos in
                engine.handleTap(pos)
            }
            .modifier(WiggleEffect(active: engine.wiggle))

            coachBubble(engine)

            Spacer(minLength: 0)

            TutorialPadView(engine: engine)
        }
        .padding(16)
        .onChange(of: engine.finished) { _, finished in
            if finished {
                if let technique = engine.lesson.technique {
                    mastery.recordLessonCompleted(technique)
                }
                dismiss()
            }
        }
    }

    private func coachBubble(_ engine: TutorialEngine) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(engine.message)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .animation(nil, value: engine.stepIndex)
            if engine.showsNextButton {
                Button {
                    engine.next()
                } label: {
                    Text(engine.finished ? "Done" : "Next")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.paper)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 9)
                        .background(Capsule().fill(Theme.indigo))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.06), radius: 10, y: 3)
        )
        .animation(Motion.overlay, value: engine.stepIndex)
    }
}

/// Pad that routes through the tutorial engine's input filter.
struct TutorialPadView: View {
    let engine: TutorialEngine

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(1...9, id: \.self) { digit in
                Button {
                    engine.handleDigit(digit)
                } label: {
                    Text("\(digit)")
                        .font(Theme.digitFont(size: 22))
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface))
                }
                .buttonStyle(.plain)
            }
            Button {
                engine.game.notesMode.toggle()
            } label: {
                Image(systemName: engine.game.notesMode ? "pencil.circle.fill" : "pencil.circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(engine.game.notesMode ? Theme.paper : Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(engine.game.notesMode ? Theme.indigo : Theme.surface)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Notes")
        }
    }
}

struct WiggleEffect: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .offset(x: active ? -6 : 0)
            .animation(active
                       ? .spring(response: 0.12, dampingFraction: 0.3)
                       : .default, value: active)
    }
}
