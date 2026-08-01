import SwiftUI

/// The play screen: board, pad, toolbar, hints, pause and win states.
struct GameView: View {
    let game: KakuroGame
    @Environment(ProgressStore.self) private var progress
    @Environment(MasteryTracker.self) private var mastery
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(PaywallPresenter.self) private var paywall
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var hint: Hint?
    @State private var hintEngine = HintEngine()
    @State private var tappedClue: ClueSelection?
    @State private var sweep: [GridPosition: Int] = [:]
    @State private var showWinSheet = false

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            layout
                .padding(16)
            if game.phase == .paused {
                pauseOverlay
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .task(id: game.phase) {
            guard game.phase == .playing else { return }
            while !Task.isCancelled {
                game.tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onChange(of: game.phase) { _, phase in
            if phase == .won {
                progress.clearSavedGame()
                let isRecord = progress.recordSolve(
                    size: sizeOf(game.puzzle), difficulty: game.generated.difficulty,
                    time: game.elapsed)
                _ = isRecord
                Haptics.win()
                showWinSheet = true
            } else {
                progress.saveGame(game.snapshot)
            }
        }
        .onChange(of: game.board.entries) { old, new in
            handleEntriesChange(old: old, new: new)
        }
        // Persist as the player works. Phase changes alone are not enough: a
        // game that is started and never paused never changes phase, so quitting
        // mid-puzzle used to lose the whole board.
        .onChange(of: game.board) { _, _ in persist() }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { persist() }
        }
        .onDisappear { persist() }
        .sheet(isPresented: $showWinSheet) { winSheet }
        .sheet(item: $tappedClue) { selection in
            CombinationSheet(selection: selection) { game.remainingCombinations(for: $0) }
        }
        .safeAreaInset(edge: .bottom) {
            if let hint {
                HintBanner(hint: hint) {
                    advanceHint()
                } onApply: {
                    game.apply(hint.application)
                    self.hint = nil
                } onDismiss: {
                    self.hint = nil
                } onUnlock: {
                    paywall.present(.teachingHints)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(Motion.overlay, value: hint != nil)
    }

    // MARK: - Layout

    /// Board beside the pad when the space is wider than it is tall, stacked
    /// otherwise. Keyed on the actual shape rather than the size class: an iPad
    /// in portrait is `.regular` but tall, and the side-by-side arrangement left
    /// the board using a quarter of the screen with the rest empty.
    private var layout: some View {
        GeometryReader { proxy in
            if proxy.size.width > proxy.size.height {
                HStack(spacing: 32) {
                    boardSection
                    VStack(spacing: 20) {
                        statusRow
                        NumberPadView(game: game)
                            .frame(maxWidth: 420)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    statusRow
                    // Slack above and below so the board sits optically centred
                    // in the space between status row and pad, rather than
                    // hanging off the top with a dead gap under it.
                    Spacer(minLength: 0)
                    boardSection
                    Spacer(minLength: 0)
                    NumberPadView(game: game)
                        .frame(maxWidth: 560)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var boardSection: some View {
        BoardView(game: game, highlighted: hintHighlights, sweep: sweep) { pos in
            handleTap(pos)
        }
    }

    private var hintHighlights: Set<GridPosition> {
        guard let hint, hint.level >= .highlight else { return [] }
        return Set(hint.highlightCells)
    }

    private var statusRow: some View {
        HStack {
            Text(game.generated.difficulty.displayName)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.inkSoft)
            Spacer()
            Text(formatTime(game.elapsed))
                .font(.subheadline.weight(.medium).monospacedDigit())
                .foregroundStyle(Theme.inkSoft)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                requestHint()
            } label: {
                Image(systemName: "lightbulb")
            }
            .accessibilityLabel("Hint")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button("Auto notes") { game.fillAutoNotes() }
                Button(game.phase == .paused ? "Resume" : "Pause") {
                    game.phase == .paused ? game.resume() : game.pause()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    // MARK: - Interactions

    private func handleTap(_ pos: GridPosition) {
        switch game.puzzle.cells[pos.row][pos.col] {
        case .white:
            game.tap(pos)
        case .clue:
            // Tap a clue to see which digit sets still fit its run(s).
            let runs = game.puzzle.runs.filter { $0.clueCell == pos }
            guard !runs.isEmpty else { return }
            tappedClue = ClueSelection(position: pos, runs: runs)
            Haptics.note()
        case .block:
            break
        }
    }

    /// Snapshots the game unless it is finished — a won board clears its save
    /// instead, and must not resurrect it on the way out.
    private func persist() {
        guard game.phase != .won else { return }
        progress.saveGame(game.snapshot)
    }

    /// Free players keep the error check ("something here is wrong"); the
    /// teaching ladder is part of the unlock.
    private var hintPolicy: HintPolicy {
        entitlements.isUnlocked ? .full : .errorsOnly
    }

    private func requestHint() {
        hint = hintEngine.hint(for: game, mastery: mastery,
                               showErrors: progress.settings.showErrors,
                               policy: hintPolicy)
    }

    private func advanceHint() {
        guard let current = hint else { return }
        guard !current.isLocked else {
            paywall.present(.teachingHints)
            return
        }
        hint = hintEngine.escalate(current, for: game, mastery: mastery, policy: hintPolicy)
    }

    private func handleEntriesChange(old: [GridPosition: Int], new: [GridPosition: Int]) {
        // Mastery: does the new entry match the pending logical step?
        if new.count == old.count + 1,
           let added = new.first(where: { old[$0.key] == nil }) {
            mastery.recordEntry(position: added.key, digit: added.value, game: game)
        }
        // Run-completion sweep.
        var completed: [GridPosition: Int] = [:]
        for run in game.puzzle.runs where game.isRunComplete(run) {
            let wasComplete = run.cells.allSatisfy { old[$0] != nil }
            if !wasComplete {
                for (index, cell) in run.cells.enumerated() {
                    completed[cell] = index
                }
            }
        }
        if !completed.isEmpty {
            Haptics.runComplete()
            withAnimation(Motion.runComplete) { sweep = completed }
            Task {
                try? await Task.sleep(for: .seconds(0.7))
                withAnimation(Motion.runComplete) { sweep = [:] }
            }
        }
        hint = nil
    }

    // MARK: - Win

    private var winSheet: some View {
        VStack(spacing: 20) {
            Text("Solved")
                .font(Theme.title)
                .foregroundStyle(Theme.ink)
            Text(formatTime(game.elapsed))
                .font(Theme.digitFont(size: 40))
                .foregroundStyle(Theme.indigo)
            if let best = progress.bestTime(size: sizeOf(game.puzzle),
                                            difficulty: game.generated.difficulty) {
                Text(best >= game.elapsed ? "New best time" : "Best: \(formatTime(best))")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
            }
            TechniqueRecapView(profile: game.generated.techniqueProfile)
            Button {
                showWinSheet = false
                dismiss()
            } label: {
                Text("Done")
                    .font(.headline)
                    .foregroundStyle(Theme.paper)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.indigo))
            }
            .buttonStyle(.plain)
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationBackground(Theme.paper)
    }

    private var pauseOverlay: some View {
        ZStack {
            Theme.paper.opacity(0.96).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("Paused")
                    .font(Theme.heading)
                    .foregroundStyle(Theme.ink)
                Button {
                    game.resume()
                } label: {
                    Text("Resume")
                        .font(.headline)
                        .foregroundStyle(Theme.paper)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(Theme.indigo))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sizeOf(_ puzzle: KakuroPuzzle) -> BoardSize {
        BoardSize.allCases.first { $0.dimension == puzzle.rows } ?? .small
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

/// Which techniques this puzzle exercised — the win screen teaches too.
struct TechniqueRecapView: View {
    let profile: [Technique: Int]

    var body: some View {
        let used = profile.filter { $0.value > 0 }.keys.sorted()
        if !used.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Techniques in this puzzle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.inkSoft)
                ForEach(used) { technique in
                    HStack {
                        Text(technique.displayName)
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                        Spacer()
                        Text("\(profile[technique] ?? 0)×")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
        }
    }
}
