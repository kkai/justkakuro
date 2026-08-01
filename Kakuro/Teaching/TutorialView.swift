import SwiftUI

/// Plays one scripted lesson: board on top, coach bubble below, filtered input.
struct TutorialView: View {
    let technique: Technique?
    @Environment(MasteryTracker.self) private var mastery
    @Environment(\.dismiss) private var dismiss

    @State private var engine: TutorialEngine?
    @State private var tappedClue: ClueSelection?
    @State private var fraction: Double = 0
    @State private var startedAt = Date.now

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            if let engine {
                lessonBody(engine)
            } else {
                PuzzleLoadingView(fraction: fraction, startedAt: startedAt) { dismiss() }
            }
        }
        .navigationTitle(engine?.lesson.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard engine == nil else { return }
            // Baked lessons resolve immediately; the rest search for a board and
            // must be interruptible, or backing out leaves the work running.
            if let baked = TutorialPuzzles.bakedLesson(for: technique) {
                engine = TutorialEngine(lesson: baked)
            } else if let technique, let lesson = await buildLesson(technique) {
                engine = TutorialEngine(lesson: lesson)
            }
        }
    }

    private func buildLesson(_ technique: Technique) async -> TutorialLesson? {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Double.self, bufferingPolicy: .bufferingNewest(1))
        let task = Task { @MainActor () -> TutorialLesson? in
            let control = KakuroGenerator.Control(
                isCancelled: { Task.isCancelled },
                onProgress: { continuation.yield($0) })
            let lesson = await TutorialPuzzles.generatedLesson(for: technique, control: control)
            continuation.finish()
            return Task.isCancelled ? nil : lesson
        }
        let watcher = Task { @MainActor in
            for await value in stream { fraction = max(fraction, value) }
        }
        defer { watcher.cancel() }
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func lessonBody(_ engine: TutorialEngine) -> some View {
        VStack(spacing: 14) {
            BoardView(game: engine.game, highlighted: engine.highlightedCells) { pos in
                handleTap(pos, engine: engine)
            }
            .modifier(WiggleEffect(active: engine.wiggle))

            coachBubble(engine)

            Spacer(minLength: 0)

            TutorialPadView(engine: engine)
        }
        .padding(16)
        // Match every other screen: without this the pad stretches
        // across a 13-inch iPad, giving ~190pt digit keys.
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .sheet(item: $tappedClue) { selection in
            CombinationSheet(selection: selection) { engine.game.remainingCombinations(for: $0) }
        }
        .onChange(of: engine.finished) { _, finished in
            if finished {
                if let technique = engine.lesson.technique {
                    mastery.recordLessonCompleted(technique)
                }
                dismiss()
            }
        }
    }

    /// Clue taps open the combination sheet at any point in a lesson — the
    /// scripts promise it, and `TutorialEngine` would otherwise reject the tap
    /// with an error haptic. White cells stay under the script's control.
    private func handleTap(_ pos: GridPosition, engine: TutorialEngine) {
        switch engine.game.puzzle.cells[pos.row][pos.col] {
        case .clue:
            let runs = engine.game.puzzle.runs.filter { $0.clueCell == pos }
            guard !runs.isEmpty else { return }
            tappedClue = ClueSelection(position: pos, runs: runs)
            Haptics.note()
        case .white:
            engine.handleTap(pos)
        case .block:
            break
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
