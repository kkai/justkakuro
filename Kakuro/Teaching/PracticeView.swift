import SwiftUI

/// A drill: solve a small board built around one technique. Solving without
/// hints advances mastery.
struct PracticeView: View {
    let technique: Technique
    @Environment(MasteryTracker.self) private var mastery
    @Environment(\.dismiss) private var dismiss

    @State private var game: KakuroGame?
    @State private var usedHint = false
    @State private var hint: Hint?
    @State private var hintEngine = HintEngine()
    @State private var variant: UInt64 = 0

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            if let game {
                drillBody(game)
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Building a drill…")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSoft)
                }
            }
        }
        .navigationTitle(technique.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: variant) {
            game = nil
            usedHint = false
            hint = nil
            let v = variant
            let generated = await Task.detached(priority: .userInitiated) {
                PracticeDrills.drillPuzzle(for: technique, variant: v)
            }.value
            game = KakuroGame(puzzle: generated)
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
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
