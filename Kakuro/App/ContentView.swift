import SwiftUI

struct ContentView: View {
    @Environment(ProgressStore.self) private var progress
    @Environment(PuzzleCache.self) private var cache

    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path)
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                }
        }
        .tint(Theme.indigo)
        .task {
            cache.prefetch(size: .small, difficulty: .easy)
            cache.prefetch(size: .small, difficulty: .medium)
        }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .game(let size, let difficulty):
            GameLoaderView(size: size, difficulty: difficulty)
        case .resumeGame:
            if let snapshot = progress.loadSavedGame() {
                GameHostView(game: KakuroGame(snapshot: snapshot))
            } else {
                MissingSaveView()
            }
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

    @State private var game: KakuroGame?

    var body: some View {
        Group {
            if let game {
                GameHostView(game: game)
            } else {
                ZStack {
                    Theme.paper.ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Preparing a fresh puzzle…")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSoft)
                    }
                }
            }
        }
        .task {
            guard game == nil else { return }
            let generated = await cache.takePuzzle(size: size, difficulty: difficulty)
            let fresh = KakuroGame(puzzle: generated)
            if progress.settings.autoNotes {
                fresh.fillAutoNotes()
            }
            game = fresh
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
            Text("That game is finished — start a new one from Home.")
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
}
