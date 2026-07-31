import Foundation
import Observation

/// Pre-generates the next puzzle per (size, difficulty) off the main actor so
/// starting a game never blocks on generation.
@Observable @MainActor
final class PuzzleCache {
    private var cache: [CacheKey: GeneratedPuzzle] = [:]
    private var inFlight: Set<CacheKey> = []

    struct CacheKey: Hashable {
        let size: BoardSize
        let difficulty: Difficulty
    }

    /// Returns a puzzle immediately if cached, otherwise generates one.
    /// Always kicks off a background refill for the requested key.
    func takePuzzle(size: BoardSize, difficulty: Difficulty) async -> GeneratedPuzzle {
        let key = CacheKey(size: size, difficulty: difficulty)
        if let cached = cache.removeValue(forKey: key) {
            prefetch(size: size, difficulty: difficulty)
            return cached
        }
        let generated = await Self.generate(size: size, difficulty: difficulty)
        prefetch(size: size, difficulty: difficulty)
        return generated
    }

    /// Warms the cache for a key (call at launch for likely picks).
    func prefetch(size: BoardSize, difficulty: Difficulty) {
        let key = CacheKey(size: size, difficulty: difficulty)
        guard cache[key] == nil, !inFlight.contains(key) else { return }
        inFlight.insert(key)
        Task {
            let generated = await Self.generate(size: size, difficulty: difficulty)
            self.cache[key] = generated
            self.inFlight.remove(key)
        }
    }

    private static func generate(size: BoardSize, difficulty: Difficulty) async -> GeneratedPuzzle {
        let options = KakuroGenerator.Options(size: size, difficulty: difficulty)
        return await Task.detached(priority: .userInitiated) {
            KakuroGenerator.generate(options)
        }.value
    }
}
