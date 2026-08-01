import SwiftUI

struct ContentView: View {
    @Environment(ProgressStore.self) private var progress
    @Environment(PuzzleCache.self) private var cache
    @Environment(PaywallPresenter.self) private var paywall

    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path)
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                }
        }
        .tint(Theme.indigo)
        // One paywall for the whole app, rooted above the NavigationStack so it
        // presents identically from Home and from any pushed destination.
        .sheet(item: Binding(get: { paywall.context },
                             set: { if $0 == nil { paywall.dismiss() } })) { context in
            PaywallView(context: context)
        }
        // No launch-time prewarm: HomeView warms the key its pickers point at,
        // restored from the last game played. Warming (.small, *) here bought
        // almost nothing — small boards generate in ~0.03s — while every medium
        // and large key stayed cold.
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .game(let size, let difficulty):
            GameLoaderView(size: size, difficulty: difficulty)
        case .resumeGame:
            ResumeGameView()
        case .tutorial(let technique):
            TutorialView(technique: technique)
        case .practice(let technique):
            PracticeView(technique: technique)
        case .learn:
            LearnMenuView(path: $path)
        case .practiceMenu:
            PracticeMenuView(path: $path)
        case .stats:
            StatsView()
        case .settings:
            SettingsView()
        }
    }
}

/// Waits for the puzzle cache (usually instant), then hosts the game.
struct GameLoaderView: View {
    let size: BoardSize
    let difficulty: Difficulty
    @Environment(PuzzleCache.self) private var cache
    @Environment(ProgressStore.self) private var progress

    @Environment(\.dismiss) private var dismiss

    @State private var game: KakuroGame?
    @State private var fraction: Double = 0
    @State private var startedAt = Date.now

    var body: some View {
        Group {
            if let game {
                GameHostView(game: game)
            } else {
                PuzzleLoadingView(fraction: fraction, startedAt: startedAt) { dismiss() }
            }
        }
        .task {
            guard game == nil else { return }
            // Recorded before the await so a player who backgrounds during a
            // slow build still has their choice remembered next launch. The
            // *requested* difficulty, not the delivered band — generate returns
            // nearest-band on budget exhaustion, and persisting that would make
            // the picker silently jump.
            progress.recordLastPlayed(size: size, difficulty: difficulty)

            // Obtained synchronously, before the first suspension, so no
            // progress is missed and the entry cannot be rebuilt underneath us.
            let request = cache.request(size: size, difficulty: difficulty)
            let watcher = Task { @MainActor in
                for await value in request.progress {
                    fraction = max(fraction, value)
                }
            }
            defer { watcher.cancel() }

            // nil means cancelled — this view is on its way out.
            guard let generated = await request.puzzle() else { return }
            let fresh = KakuroGame(puzzle: generated, requestedDifficulty: difficulty)
            if progress.settings.autoNotes {
                fresh.fillAutoNotes()
            }
            game = fresh
        }
    }
}

/// Resolves the saved game **once**, on entry.
///
/// Reading `progress.savedGame` directly in the navigation destination meant the
/// destination re-evaluated whenever the store changed — and winning clears the
/// save, so the live game was swapped out for `MissingSaveView` mid-celebration
/// and the win sheet never appeared. The game must outlive its own save.
struct ResumeGameView: View {
    @Environment(ProgressStore.self) private var progress

    @State private var game: KakuroGame?
    @State private var resolved = false

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            if let game {
                GameHostView(game: game)
            } else if resolved {
                MissingSaveView()
            }
        }
        .onAppear {
            guard !resolved else { return }
            if let snapshot = progress.loadSavedGame() {
                game = KakuroGame(snapshot: snapshot)
            }
            resolved = true
        }
    }
}

/// Owns the game instance for the screen's lifetime.
struct GameHostView: View {
    @State var game: KakuroGame

    var body: some View {
        GameView(game: game)
    }
}

struct MissingSaveView: View {
    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            Text("That game is finished. Start a new one from Home.")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
                .padding()
        }
    }
}

#Preview {
    ContentView()
        .environment(ProgressStore())
        .environment(PuzzleCache())
        .environment(MasteryTracker())
        .environment(EntitlementStore(source: PreviewEntitlementSource(owned: true)))
        .environment(PaywallPresenter())
}
