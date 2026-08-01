import SwiftUI

/// A drill: solve a small board built around one technique. Solving without
/// hints advances mastery.
struct PracticeView: View {
    let technique: Technique
    @Environment(MasteryTracker.self) private var mastery
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(PaywallPresenter.self) private var paywall
    @Environment(\.dismiss) private var dismiss

    @State private var game: KakuroGame?
    @State private var usedHint = false
    @State private var hint: Hint?
    @State private var hintEngine = HintEngine()
    @State private var variant: UInt64 = 0
    @State private var fraction: Double = 0
    @State private var startedAt = Date.now

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            if !entitlements.isUnlocked {
                LockedFeatureView(feature: .practiceDrills)
            } else if let game {
                drillBody(game)
            } else {
                PuzzleLoadingView(fraction: fraction, startedAt: startedAt) { dismiss() }
            }
        }
        .navigationTitle(technique.displayName)
        .navigationTitleDisplay(.inline)
        .puzzleKeyboard { command in
            // Keys do nothing while the drill is still being generated, or when
            // the screen is showing the paywall instead of a board.
            guard let game else { return }
            game.handle(command)
            if case .digit = command { Haptics.tap() }
        }
        .task(id: variant) {
            // Guard before generating: a drill search is expensive, and this
            // route can be reached with a stale path after a refund.
            guard entitlements.isUnlocked else { return }
            game = nil
            usedHint = false
            hint = nil
            fraction = 0
            startedAt = .now
            let v = variant
            let generated = await buildDrill(variant: v)
            guard let generated else { return }   // cancelled; the view is leaving
            game = KakuroGame(puzzle: generated)
        }
    }

    /// Runs the drill search on a detached task whose cancellation actually
    /// reaches the generator, so backing out stops the work instead of leaving
    /// it to run on invisibly.
    private func buildDrill(variant: UInt64) async -> GeneratedPuzzle? {
        let technique = self.technique
        let (stream, continuation) = AsyncStream.makeStream(
            of: Double.self, bufferingPolicy: .bufferingNewest(1))
        let task = Task.detached(priority: .userInitiated) { () -> GeneratedPuzzle? in
            let control = KakuroGenerator.Control(
                isCancelled: { Task.isCancelled },
                onProgress: { continuation.yield($0) })
            let drill = PracticeDrills.drillPuzzle(for: technique, variant: variant,
                                                   control: control)
            continuation.finish()
            return Task.isCancelled ? nil : drill
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

    private func drillBody(_ game: KakuroGame) -> some View {
        VStack(spacing: 14) {
            Text(TechniqueContent.rule(for: technique))
                .font(.footnote)
                .foregroundStyle(Theme.inkSoft)
                .frame(maxWidth: .infinity, alignment: .leading)
            BoardView(game: game, highlighted: hintCells)
            Spacer(minLength: 0)
            NumberPadView(game: game)
        }
        .padding(16)
        // Match every other screen: without this the pad stretches
        // across a 13-inch iPad, giving ~190pt digit keys.
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
        .toolbar {
            ToolbarItem(placement: .primaryTrailing) {
                Button {
                    usedHint = true
                    hint = hint.map { hintEngine.escalate($0, for: game, mastery: mastery) }
                        ?? hintEngine.hint(for: game, mastery: mastery)
                } label: {
                    Image(systemName: "lightbulb")
                }
                .accessibilityLabel("Hint")
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let hint {
                HintBanner(hint: hint) {
                    usedHint = true
                    self.hint = hintEngine.escalate(hint, for: game, mastery: mastery)
                } onApply: {
                    game.apply(hint.application)
                    self.hint = nil
                } onDismiss: {
                    self.hint = nil
                } onUnlock: {
                    paywall.present(.teachingHints)
                }
                .padding(.horizontal, 16)
            }
        }
        .onChange(of: game.phase) { _, phase in
            guard phase == .won else { return }
            mastery.recordDrillCompleted(technique, unaided: !usedHint)
            Haptics.win()
        }
        .overlay {
            if game.phase == .won {
                drillWonOverlay
            }
        }
    }

    private var hintCells: Set<GridPosition> {
        guard let hint, hint.level >= .highlight else { return [] }
        return Set(hint.highlightCells)
    }

    private var drillWonOverlay: some View {
        ZStack {
            Theme.paper.opacity(0.95).ignoresSafeArea()
            VStack(spacing: 16) {
                Text(usedHint ? "Solved" : "Solved unaided")
                    .font(Theme.heading)
                    .foregroundStyle(Theme.ink)
                let record = mastery.record(for: technique)
                Text("\(record.unaidedUses)/\(MasteryTracker.learnedThreshold) unaided toward Learned")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
                HStack(spacing: 12) {
                    Button {
                        variant += 1
                    } label: {
                        Text("Another drill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.paper)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 11)
                            .background(Capsule().fill(Theme.indigo))
                    }
                    .buttonStyle(.plain)
                    Button {
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.indigo)
                    }
                }
            }
            .padding(24)
        }
    }
}
