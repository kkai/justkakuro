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
    /// Set when the player taps Apply on a hint, consumed by the next entry
    /// change so that placement does not count toward unaided mastery.
    @State private var appliedHint = false
    @State private var newBestTime = false
    #if os(tvOS)
    /// tvOS only: Select on a focused cell opens the digit chooser.
    @State private var choosingDigit = false
    #endif

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            layout
                .padding(16)
            if game.phase == .paused {
                pauseOverlay
            }
            #if os(tvOS)
            if choosingDigit {
                Color.black.opacity(0.45).ignoresSafeArea()
                DigitChooser(notesMode: game.notesMode,
                             canErase: game.selected.map { game.board.entry(at: $0) != nil
                                 || !game.board.notes(at: $0).isEmpty } ?? false) { command in
                    game.handle(command)
                } close: {
                    choosingDigit = false
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
            #endif
        }
        #if os(tvOS)
        .animation(Motion.overlay, value: choosingDigit)
        #endif
        .navigationTitleDisplay(.inline)
        .puzzleKeyboard { command in
            game.handle(command)
            if case .digit = command { Haptics.tap() }
        }
        #if !os(tvOS)
        .toolbar { toolbarContent }
        #endif
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
                newBestTime = progress.recordSolve(
                    size: sizeOf(game.puzzle), difficulty: game.difficultyForRecords,
                    time: game.elapsed)
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
            if phase != .active {
                // Pause, don't just save. `tick` adds a wall-clock delta, and
                // Task.sleep runs on a continuous clock, so without this the
                // first tick after returning folds the entire background
                // interval into `elapsed` — an overnight background added ~8
                // hours to lifetime play time and could poison a first best
                // time. Pausing clears `lastTick` and stops the timer task.
                game.pause()
                persist()
            }
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
                    // Consumed by handleEntriesChange: the placement this makes
                    // is the hint's work, not the player's.
                    appliedHint = true
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
                #if os(tvOS)
                // Its own section, so focus can leave the banner and return to
                // the board rather than being caught by whichever of its four
                // buttons happens to be nearest.
                .focusSection()
                #endif
            }
        }
        .animation(Motion.overlay, value: hint != nil)
    }

    // MARK: - Layout

    /// Board beside the pad when the space is wider than it is tall, stacked
    /// otherwise. Keyed on the actual shape rather than the size class: an iPad
    /// in portrait is `.regular` but tall, and the side-by-side arrangement left
    /// the board using a quarter of the screen with the rest empty.
    @ViewBuilder
    private var layout: some View {
        #if os(tvOS)
        // No keypad on screen. It would be focusable, so the remote could walk
        // off the board into it, and then every digit would cost a trip across
        // the screen and back. The chooser opens where the eye already is.
        VStack(spacing: 24) {
            HStack(spacing: 16) {
                statusRow
                tvControls
            }
            .frame(maxWidth: Metrics.column)
            boardSection
            Text(game.selected == nil
                 ? "Move with the remote to pick a square"
                 : "Press Select to enter a digit")
                .font(.title3)
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        legacyLayout
        #endif
    }

    /// Hint and the overflow menu, in the content rather than the toolbar.
    ///
    /// On tvOS a toolbar is its own focus container, sitting outside the view
    /// tree the board lives in. Focus could climb into it and then had no way
    /// back down: `focusSection` on the board did not help, because the two are
    /// not in the same focus space to begin with. Rendering the controls as
    /// ordinary buttons in the same stack as the board makes up and down mean
    /// what they look like they mean.
    #if os(tvOS)
    private var tvControls: some View {
        HStack(spacing: 12) {
            Button { requestHint() } label: {
                Label("Hint", systemImage: "lightbulb")
            }
            .accessibilityLabel("Hint")
            Button { game.fillAutoNotes() } label: {
                Label("Auto notes", systemImage: "pencil.circle")
            }
            Button {
                game.phase == .paused ? game.resume() : game.pause()
            } label: {
                Label(game.phase == .paused ? "Resume" : "Pause",
                      systemImage: game.phase == .paused ? "play" : "pause")
            }
        }
        .buttonStyle(.kakuro)
        .focusSection()
    }
    #endif

    private var legacyLayout: some View {
        GeometryReader { proxy in
            if proxy.size.width > proxy.size.height {
                HStack(spacing: 32) {
                    boardSection
                    VStack(spacing: 20) {
                        statusRow
                        NumberPadView(game: game)
                    }
                    // The cap belongs to the whole column, not just the pad.
                    // statusRow stretches to fill its width, so capping only the
                    // pad left the column expanding and pushed the keypad away
                    // from the board with the difficulty and timer strung out
                    // across the gap.
                    .frame(maxWidth: 420)
                }
                // Centred on both axes: a GeometryReader aligns its content
                // top-leading, which left a Mac window with the board jammed
                // into the top-left and the bottom half empty.
                //
                // The cap keeps the two halves together. Without it the pad
                // column expands to fill whatever is left and the board and
                // keypad drift to opposite edges of a wide window. 1120 is
                // deliberate: minus the 420 pad and 32 spacing it leaves 668 for
                // the board, which is just past what a small board can use at
                // the 88pt cell cap, so the board reaches its own limit rather
                // than being squeezed by this one.
                .frame(maxWidth: 1120)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                        .frame(maxWidth: Metrics.column)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// Grouped as a focus section on tvOS.
    ///
    /// Without it, focus that has climbed into the toolbar or dropped into the
    /// hint banner cannot get back: the engine looks for a focusable view
    /// directly along the direction of travel, and the cell it needs is usually
    /// offset, or the nearest thing below the toolbar is a black cell, which is
    /// deliberately not focusable. A section lets the engine aim at the group
    /// and land on the nearest cell inside it, and `@FocusState` still holds the
    /// cell you left, so you come back where you were.
    private var boardSection: some View {
        BoardView(game: game, highlighted: hintHighlights, sweep: sweep,
                  onTap: { pos in handleTap(pos) },
                  onActivate: { _ in
                      #if os(tvOS)
                      choosingDigit = true
                      #endif
                  })
        #if os(tvOS)
        .focusSection()
        #endif
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
        ToolbarItem(placement: .primaryTrailing) {
            Button {
                requestHint()
            } label: {
                Image(systemName: "lightbulb")
            }
            .accessibilityLabel("Hint")
        }
        ToolbarItem(placement: .primaryTrailing) {
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
        let wasApplied = appliedHint
        appliedHint = false
        if new.count == old.count + 1,
           let added = new.first(where: { old[$0.key] == nil }) {
            let firstTimeHere = game.claimMasteryCredit(at: added.key)
            mastery.recordEntry(position: added.key, digit: added.value, game: game,
                                unaided: !wasApplied && firstTimeHere)
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
            // Taken from recordSolve rather than re-derived by comparing against
            // a store that has already been updated: on an exact tie the old
            // comparison claimed a new best that was never recorded.
            if newBestTime {
                Text("New best time")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSoft)
            } else if let best = progress.bestTime(size: sizeOf(game.puzzle),
                                                   difficulty: game.difficultyForRecords) {
                Text("Best: \(formatTime(best))")
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
            .buttonStyle(.kakuro)
        }
        .padding(24)
        .mediumSheet()
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
                .buttonStyle(.kakuro)
            }
        }
    }

    private func sizeOf(_ puzzle: KakuroPuzzle) -> BoardSize {
        BoardSize.allCases.first { $0.dimension == puzzle.rows } ?? .small
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        TimeFormatting.clock(interval)
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
