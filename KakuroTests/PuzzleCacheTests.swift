import Foundation
import Testing
@testable import Kakuro

/// These exist because `PuzzleCache` had none, which is exactly how the
/// double-generation bug shipped. The `generate` seam keeps them sub-millisecond.
@MainActor
@Suite struct PuzzleCacheTests {

    /// A controllable stand-in for the generator: counts calls, and can be held
    /// open so a test can observe the in-flight window.
    /// `nonisolated` because the project defaults every unannotated type to
    /// MainActor, and this is called from the generator's detached task.
    private nonisolated final class FakeGenerator: @unchecked Sendable {
        private let lock = NSLock()
        private var _calls = 0
        private var _released = false

        var calls: Int { lock.withLock { _calls } }

        func release() { lock.withLock { _released = true } }

        /// Blocks until released, so the entry stays in flight.
        func generate(_ options: KakuroGenerator.Options,
                      _ control: KakuroGenerator.Control) -> GeneratedPuzzle {
            lock.withLock { _calls += 1 }
            while !lock.withLock({ _released }) {
                if control.isCancelled() { break }
                usleep(200)
            }
            let puzzle = KakuroBuilder.puzzle(fromSolutionGrid: [
                [nil, nil, nil],
                [nil, 1, 2],
                [nil, 3, 5],
            ])
            return GeneratedPuzzle(puzzle: puzzle, difficulty: options.difficulty,
                                   techniqueProfile: [:])
        }
    }

    private func makeCache(_ fake: FakeGenerator) -> PuzzleCache {
        PuzzleCache(generate: { fake.generate($0, $1) })
    }

    /// The headline regression: `takePuzzle` used to ignore `inFlight` and start
    /// a second generation, leaving the player waiting on the *later* one.
    @Test func requestAwaitsAnInFlightWarmInsteadOfStartingASecond() async {
        let fake = FakeGenerator()
        let cache = makeCache(fake)

        cache.warm(size: .small, difficulty: .easy)
        // Let the warm task actually enter the generator.
        await waitUntil("the generator to start") { fake.calls >= 1 }

        let request = cache.request(size: .small, difficulty: .easy)
        // Assert here, not after awaiting: consuming a puzzle deliberately
        // re-warms the key, which would make the count 2 for a good reason and
        // hide the bad one.
        #expect(fake.calls == 1, "a claim on an in-flight warm must not start a second generation")

        fake.release()
        #expect(await request.puzzle() != nil)
    }

    @Test func warmingANewKeyCancelsThePreviousUnclaimedWarm() async {
        let fake = FakeGenerator()
        let cache = makeCache(fake)

        cache.warm(size: .small, difficulty: .easy)
        await waitUntil("the generator to start") { fake.calls >= 1 }
        // Superseding warm — the first is speculative and unclaimed, so it goes.
        cache.warm(size: .medium, difficulty: .hard)
        await waitUntil("the second generation to start") { fake.calls >= 2 }

        // Exactly two: the cancelled one and the survivor. Checked before any
        // claim, so the re-warm cannot inflate it.
        #expect(fake.calls == 2, "the superseding warm should not have started a third generation")

        fake.release()
        #expect(await cache.request(size: .medium, difficulty: .hard).puzzle() != nil)
    }

    /// A cancelled entry must be *removed*: it resolves to nil forever, so
    /// leaving it in the table would hang every later request for that key.
    @Test func cancellingDropsTheEntrySoALaterRequestStartsFresh() async {
        let fake = FakeGenerator()
        let cache = makeCache(fake)

        let request = cache.request(size: .small, difficulty: .easy)
        await waitUntil("the generator to start") { fake.calls >= 1 }

        let consumer = Task { await request.puzzle() }
        consumer.cancel()
        let cancelled = await consumer.value
        #expect(cancelled == nil, "a cancelled request yields nil")

        // The key must be usable again rather than permanently poisoned.
        fake.release()
        let second = await cache.request(size: .small, difficulty: .easy).puzzle()
        #expect(second != nil, "a later request for a cancelled key must not hang on nil")
    }

    @Test func afterTakingAPuzzleTheKeyIsRewarmed() async {
        let fake = FakeGenerator()
        let cache = makeCache(fake)
        fake.release()

        let first = await cache.request(size: .small, difficulty: .easy).puzzle()
        #expect(first != nil)

        // The re-warm runs on a detached task. Wait against a deadline rather
        // than spinning: under full-suite CPU load a bare yield loop can starve
        // it long enough to look like a failure.
        await waitUntil("the consumed key is re-warmed") { fake.calls >= 2 }
        let callsAfterRewarm = fake.calls

        // The point of the re-warm: the next claim is served by it, not by a
        // fresh generation. Asserted relatively, so an extra background warm
        // cannot turn a pass into a failure.
        let second = await cache.request(size: .small, difficulty: .easy).puzzle()
        #expect(second != nil)
        #expect(fake.calls == callsAfterRewarm,
                "the re-warm should have served the second request")
    }

    /// Polls a condition against a generous deadline.
    private func waitUntil(_ what: String, _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(condition(), "timed out waiting for \(what)")
    }

    @Test func repeatedWarmsOfTheSameKeyGenerateOnce() async {
        let fake = FakeGenerator()
        let cache = makeCache(fake)

        cache.warm(size: .small, difficulty: .easy)
        cache.warm(size: .small, difficulty: .easy)
        cache.warm(size: .small, difficulty: .easy)
        await waitUntil("the generator to start") { fake.calls >= 1 }

        #expect(fake.calls == 1, "warming an already-warm key must be a no-op")
        fake.release()
    }
}
