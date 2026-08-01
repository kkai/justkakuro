import Foundation
import Observation

/// Pre-generates the next puzzle per (size, difficulty) off the main actor so
/// starting a game rarely blocks on generation.
///
/// The table holds **tasks, not finished puzzles**. That is the whole design:
/// a request for a key that is already generating simply awaits that task, so
/// the old failure mode — a cache miss starting a *second* generation while the
/// first was still running, and the player waiting on the later one — cannot be
/// expressed. There is one table, so there is nothing to keep in sync.
@Observable @MainActor
final class PuzzleCache {

    struct CacheKey: Hashable {
        let size: BoardSize
        let difficulty: Difficulty
    }

    /// A `final class` because identity matters: a late-finishing task must not
    /// clobber a fresher entry for the same key.
    private final class Entry {
        let task: Task<GeneratedPuzzle?, Never>
        let progress: AsyncStream<Double>
        var isClaimed = false

        init(task: Task<GeneratedPuzzle?, Never>, progress: AsyncStream<Double>) {
            self.task = task
            self.progress = progress
        }
    }

    /// Not view state — nothing reads the table in a body, and marking it
    /// observed would invalidate views on every prefetch.
    @ObservationIgnored private var entries: [CacheKey: Entry] = [:]
    @ObservationIgnored private let generate:
        @Sendable (KakuroGenerator.Options, KakuroGenerator.Control) -> GeneratedPuzzle

    /// The `generate` seam mirrors `ProgressStore(userDefaults:)` — it makes the
    /// "did we generate once or twice?" question testable in milliseconds
    /// instead of seconds.
    init(generate: @escaping @Sendable (KakuroGenerator.Options, KakuroGenerator.Control)
         -> GeneratedPuzzle = { KakuroGenerator.generate($0, control: $1) }) {
        self.generate = generate
    }

    // MARK: - API

    /// Keeps a warm entry for this key, cancelling any other *running,
    /// unclaimed* generation. At most one speculative generation runs at a
    /// time: nine concurrent ones would starve the cooperative pool and make
    /// the board the player is actually waiting for slower.
    func warm(size: BoardSize, difficulty: Difficulty) {
        let key = CacheKey(size: size, difficulty: difficulty)
        for (other, entry) in entries where other != key && !entry.isClaimed {
            entry.task.cancel()
            entries.removeValue(forKey: other)
        }
        guard entries[key] == nil else { return }
        entries[key] = makeEntry(key, priority: .utility)
    }

    /// Claims this key, starting a generation only if none is running.
    func request(size: BoardSize, difficulty: Difficulty) -> PuzzleRequest {
        let key = CacheKey(size: size, difficulty: difficulty)
        let entry: Entry
        if let existing = entries[key] {
            entry = existing
        } else {
            entry = makeEntry(key, priority: .userInitiated)
            entries[key] = entry
        }
        entry.isClaimed = true
        return PuzzleRequest(task: entry.task, progress: entry.progress) { [weak self] cancelled in
            self?.settle(key, entry: entry, cancelled: cancelled)
        }
    }

    // MARK: - Internals

    private func makeEntry(_ key: CacheKey, priority: TaskPriority) -> Entry {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Double.self, bufferingPolicy: .bufferingNewest(1))
        let options = KakuroGenerator.Options(size: key.size, difficulty: key.difficulty)
        let generate = self.generate
        // Detached, so `Task.isCancelled` inside refers to the same task the
        // consumer cancels — no nesting, no second cancellation hop.
        let task = Task.detached(priority: priority) { () -> GeneratedPuzzle? in
            let control = KakuroGenerator.Control(
                isCancelled: { Task.isCancelled },
                onProgress: { continuation.yield($0) })
            let puzzle = generate(options, control)
            continuation.finish()
            return Task.isCancelled ? nil : puzzle
        }
        return Entry(task: task, progress: stream)
    }

    /// Retires a claimed entry once its consumer has the value.
    ///
    /// Identity-guarded: a task that finishes late must not remove an entry
    /// created after it.
    ///
    /// Dropping a **cancelled** entry is correctness, not tidiness — a
    /// cancelled task resolves to `nil` forever, so leaving it in the table
    /// would make every later request for that key hang on a value that never
    /// comes. Cancelled entries are dropped without re-warming; the player
    /// backed out, so speculatively rebuilding the board they abandoned is
    /// exactly the work we just cancelled.
    private func settle(_ key: CacheKey, entry: Entry, cancelled: Bool) {
        guard entries[key] === entry else { return }
        entries.removeValue(forKey: key)
        guard !cancelled else { return }
        warm(size: key.size, difficulty: key.difficulty)
    }
}

/// A claim on a puzzle: its progress stream and a handle to await.
///
/// Both are handed over in one synchronous call. Splitting them would put a
/// suspension point between "start watching progress" and "await the puzzle",
/// where updates get missed or the entry is rebuilt underneath.
@MainActor
struct PuzzleRequest {
    private let task: Task<GeneratedPuzzle?, Never>
    let progress: AsyncStream<Double>
    private let onSettled: @MainActor (Bool) -> Void

    fileprivate init(task: Task<GeneratedPuzzle?, Never>,
                     progress: AsyncStream<Double>,
                     onSettled: @escaping @MainActor (Bool) -> Void) {
        self.task = task
        self.progress = progress
        self.onSettled = onSettled
    }

    /// The generated puzzle, or `nil` if the work was cancelled.
    ///
    /// This is where a caller's cancellation finally reaches the generator:
    /// `GameLoaderView`'s `.task` is cancelled on pop → `onCancel` fires →
    /// the detached task is cancelled → `Control.isCancelled` returns true on
    /// the next repair round. Before this, `prefetch` used a parentless
    /// `Task.detached`, so backing out of a slow board still burned the full
    /// generation invisibly.
    func puzzle() async -> GeneratedPuzzle? {
        // Bind the Sendable Task locally: `onCancel` is @Sendable and may run
        // off-main, so it must not capture MainActor-isolated state.
        let handle = task
        let result = await withTaskCancellationHandler {
            await handle.value
        } onCancel: {
            handle.cancel()
        }
        onSettled(result == nil)
        return result
    }
}
