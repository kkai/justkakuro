import Foundation
import Observation

/// All persisted progress: settings, best times, stats, mastery, and the
/// in-progress game. UserDefaults + Codable with versioned keys.
@Observable @MainActor
final class ProgressStore {
    private let defaults: UserDefaults

    private enum Key {
        static let bestTimes = "kakuro.bestTimes.v1"
        static let saveGame = "kakuro.saveGame.v1"
        static let stats = "kakuro.stats.v1"
        static let mastery = "kakuro.mastery.v1"
        static let settings = "kakuro.settings.v1"
    }

    struct Settings: Codable, Equatable {
        var autoNotes = false
        var hapticsEnabled = true
        var showErrors = true
    }

    struct Stats: Codable, Equatable {
        var puzzlesSolved = 0
        var totalPlayTime: TimeInterval = 0
        var solvedBySize: [BoardSize: Int] = [:]
        var solvedByDifficulty: [Difficulty: Int] = [:]
    }

    struct BestTimeKey: Hashable, Codable {
        let size: BoardSize
        let difficulty: Difficulty
    }

    private(set) var bestTimes: [BestTimeKey: TimeInterval] = [:]
    private(set) var stats = Stats()
    /// Mirrors the persisted save. Held as observable state rather than re-read
    /// on demand so the Continue card appears the moment a game is saved —
    /// reading UserDefaults inside a view body never invalidates it.
    private(set) var savedGame: KakuroGame.Snapshot?
    var settings = Settings() {
        didSet { save(settings, key: Key.settings) }
    }

    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
        bestTimes = load([BestTimeKey: TimeInterval].self, key: Key.bestTimes) ?? [:]
        stats = load(Stats.self, key: Key.stats) ?? Stats()
        settings = load(Settings.self, key: Key.settings) ?? Settings()
        savedGame = load(KakuroGame.Snapshot.self, key: Key.saveGame)
    }

    // MARK: - Best times / stats

    func bestTime(size: BoardSize, difficulty: Difficulty) -> TimeInterval? {
        bestTimes[BestTimeKey(size: size, difficulty: difficulty)]
    }

    /// Records a solve; returns true when it's a new best time.
    @discardableResult
    func recordSolve(size: BoardSize, difficulty: Difficulty, time: TimeInterval) -> Bool {
        stats.puzzlesSolved += 1
        stats.totalPlayTime += time
        stats.solvedBySize[size, default: 0] += 1
        stats.solvedByDifficulty[difficulty, default: 0] += 1
        save(stats, key: Key.stats)

        let key = BestTimeKey(size: size, difficulty: difficulty)
        let isRecord = bestTimes[key].map { time < $0 } ?? true
        if isRecord {
            bestTimes[key] = time
            save(bestTimes, key: Key.bestTimes)
        }
        return isRecord
    }

    // MARK: - Save game

    func saveGame(_ snapshot: KakuroGame.Snapshot) {
        savedGame = snapshot
        save(snapshot, key: Key.saveGame)
    }

    func loadSavedGame() -> KakuroGame.Snapshot? {
        savedGame
    }

    func clearSavedGame() {
        savedGame = nil
        defaults.removeObject(forKey: Key.saveGame)
    }

    // MARK: - Mastery (used by MasteryTracker)

    func loadMastery<T: Decodable>(_ type: T.Type) -> T? {
        load(type, key: Key.mastery)
    }

    func saveMastery(_ value: some Encodable) {
        save(value, key: Key.mastery)
    }

    // MARK: - Codable plumbing

    private func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func save(_ value: some Encodable, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
}
