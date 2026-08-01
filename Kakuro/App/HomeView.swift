import SwiftUI

/// Home: wordmark with the diagonal signature, continue card, new game,
/// and the learning path.
struct HomeView: View {
    @Binding var path: [Route]
    @Environment(ProgressStore.self) private var progress
    @Environment(MasteryTracker.self) private var mastery
    @Environment(PuzzleCache.self) private var cache
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(PaywallPresenter.self) private var paywall

    @State private var newGameSize: BoardSize = .small
    @State private var newGameDifficulty: Difficulty = .easy
    @State private var showNewGame = false
    /// Suppresses the size gate while the pickers are being restored — see
    /// `restorePickers()`.
    @State private var isRestoring = false
    @State private var didRestore = false

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    wordmark
                        .padding(.top, 24)

                    if progress.loadSavedGame() != nil {
                        continueCard
                    }

                    newGameCard

                    HStack(spacing: 12) {
                        menuTile(title: "Learn", symbol: "book", route: .learn)
                        menuTile(title: "Practice", symbol: "target", route: .practiceMenu)
                    }
                    HStack(spacing: 12) {
                        menuTile(title: "Stats", symbol: "chart.bar", route: .stats,
                                 lockedBehind: .stats)
                        menuTile(title: "Settings", symbol: "gearshape", route: .settings)
                    }
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            guard !didRestore else { return }
            didRestore = true
            restorePickers()
            // .onChange does not fire on first appear, so this seeding call is
            // what actually warms the key the pickers point at.
            cache.warm(size: newGameSize, difficulty: newGameDifficulty)
        }
    }

    /// Restores the pickers to the last game played.
    ///
    /// `isRestoring` is load-bearing: assigning `newGameSize` fires the size
    /// gate below, and at launch `entitlements.isUnlocked` is still false while
    /// StoreKit resolves — so a *paying* customer whose last game was large
    /// would be shown a paywall the moment the app opened.
    private func restorePickers() {
        guard let choice = progress.lastPlayed else { return }
        isRestoring = true
        defer { isRestoring = false }
        // Still respect the gate. Someone who does not own large simply keeps
        // the default size — quietly, with no sheet.
        if FeatureGate.isSizeAvailable(choice.size, unlocked: entitlements.isUnlocked) {
            newGameSize = choice.size
        }
        newGameDifficulty = choice.difficulty
    }

    /// The wordmark: serif title crossed by the clue-cell diagonal.
    private var wordmark: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Whole-lockup fitting rather than minimumScaleFactor: the two Texts
            // would otherwise each pick their own scale and drift apart, taking
            // the diagonal off the K with them.
            ViewThatFits(in: .horizontal) {
                lockup(fontSize: 44)
                lockup(fontSize: 38)
                lockup(fontSize: 32)
            }
            Text("The crossword of sums")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
        }
    }

    /// "Just Kakuro" with the clue-cell diagonal struck through the K. The
    /// diagonal is an overlay on the "Kakuro" Text, so it tracks that word
    /// wherever the prefix puts it — the old version anchored to the whole
    /// string's bottom-leading and slid onto the J when the name changed.
    /// Every diagonal measurement is a fraction of `fontSize` so the candidates
    /// stay internally consistent.
    private func lockup(fontSize: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(verbatim: "Just")
                .padding(.trailing, fontSize * 0.22)
            Text(verbatim: "Kakuro")
                .overlay(alignment: .bottomLeading) {
                    // Anchored to the Text's bottom edge, which sits a descender
                    // below the baseline — hence the negative y, which lifts the
                    // stroke back into the K instead of trailing into the subtitle.
                    DiagonalLine()
                        .stroke(Theme.indigo,
                                style: StrokeStyle(lineWidth: fontSize / 22, lineCap: .round))
                        .frame(width: fontSize * 0.62, height: fontSize * 0.55)
                        .offset(x: -fontSize * 0.09, y: -fontSize * 0.16)
                }
        }
        .font(.system(size: fontSize, weight: .bold, design: .serif))
        .foregroundStyle(Theme.ink)
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Just Kakuro")
    }

    private var continueCard: some View {
        Button {
            path.append(.resumeGame)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Continue")
                        .font(Theme.heading)
                        .foregroundStyle(Theme.ink)
                    if let snapshot = progress.loadSavedGame() {
                        Text("\(snapshot.generated.difficulty.displayName) · \(formatTime(snapshot.elapsed))")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.indigo)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        }
        .buttonStyle(.plain)
    }

    private var newGameCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New game")
                .font(Theme.heading)
                .foregroundStyle(Theme.ink)
            Picker("Size", selection: $newGameSize) {
                ForEach(BoardSize.allCases) { size in
                    Text(size.displayName).tag(size)
                }
            }
            .pickerStyle(.segmented)
            Picker("Difficulty", selection: $newGameDifficulty) {
                ForEach(Difficulty.allCases) { difficulty in
                    Text(difficulty.displayName).tag(difficulty)
                }
            }
            .pickerStyle(.segmented)
            Button {
                // No prefetch here — the selection is already warm, and the
                // loader claims that entry rather than racing it.
                path.append(.game(size: newGameSize, difficulty: newGameDifficulty))
            } label: {
                Text("Play")
                    .font(.headline)
                    .foregroundStyle(Theme.paper)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.indigo))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
        .onChange(of: newGameSize) { previous, size in
            guard !isRestoring else { return }
            // Snap back rather than hide the segment — a hidden feature can't be
            // sold. The warm must stay inside the guard: building a large board
            // costs seconds of CPU for a puzzle they can't open.
            guard FeatureGate.isSizeAvailable(size, unlocked: entitlements.isUnlocked) else {
                newGameSize = previous
                paywall.present(.largeBoards)
                return
            }
            cache.warm(size: size, difficulty: newGameDifficulty)
        }
        .onChange(of: newGameDifficulty) { _, difficulty in
            guard !isRestoring else { return }
            cache.warm(size: newGameSize, difficulty: difficulty)
        }
    }

    private func menuTile(title: String, symbol: String, route: Route,
                          lockedBehind feature: PaidFeature? = nil) -> some View {
        let paywalled = feature.map { !FeatureGate.isAvailable($0, unlocked: entitlements.isUnlocked) }
            ?? false
        return Button {
            if let feature, paywalled {
                paywall.present(feature)
            } else {
                path.append(route)
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Theme.indigo)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity, minHeight: 88)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
            .overlay(alignment: .topTrailing) {
                if paywalled {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.indigo)
                        .padding(10)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
