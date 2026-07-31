import SwiftUI

/// Home: wordmark with the diagonal signature, continue card, new game,
/// and the learning path.
struct HomeView: View {
    @Binding var path: [Route]
    @Environment(ProgressStore.self) private var progress
    @Environment(MasteryTracker.self) private var mastery
    @Environment(PuzzleCache.self) private var cache

    @State private var newGameSize: BoardSize = .small
    @State private var newGameDifficulty: Difficulty = .easy
    @State private var showNewGame = false

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
                        menuTile(title: "Stats", symbol: "chart.bar", route: .stats)
                        menuTile(title: "Settings", symbol: "gearshape", route: .settings)
                    }
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// The wordmark: serif title crossed by the clue-cell diagonal.
    private var wordmark: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                Text("Kakuro")
                    .font(.system(size: 44, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.ink)
                DiagonalLine()
                    .stroke(Theme.indigo, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 34, height: 34)
                    .offset(x: -8, y: 10)
                    .accessibilityHidden(true)
            }
            Text("The crossword of sums")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSoft)
        }
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
                cache.prefetch(size: newGameSize, difficulty: newGameDifficulty)
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
        .onChange(of: newGameSize) { _, size in
            cache.prefetch(size: size, difficulty: newGameDifficulty)
        }
        .onChange(of: newGameDifficulty) { _, difficulty in
            cache.prefetch(size: newGameSize, difficulty: difficulty)
        }
    }

    private func menuTile(title: String, symbol: String, route: Route) -> some View {
        Button {
            path.append(route)
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
        }
        .buttonStyle(.plain)
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let seconds = Int(interval)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
