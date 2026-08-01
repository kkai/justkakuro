import Foundation
import Testing
@testable import Kakuro

@Suite struct EntitlementTests {

    // MARK: - FeatureGate

    /// The free tier is exactly: the rules lesson, No Repeats, Magic Blocks.
    /// Spelled out as a literal set so that "simplifying" the gate later fails
    /// here rather than in the App Store.
    @Test func freeLessonsAreExactlyTheFirstThree() {
        let free = ([nil] + Technique.allCases.map { Optional($0) })
            .filter { FeatureGate.isLessonAvailable($0, unlocked: false) }
        #expect(free == [nil, .duplicateInRun, .magicBlock])
    }

    @Test func unlockingOpensEveryLesson() {
        for technique in [nil] + Technique.allCases.map({ Optional($0) }) {
            #expect(FeatureGate.isLessonAvailable(technique, unlocked: true))
        }
    }

    @Test func onlyLargeBoardsArePaid() {
        for size in BoardSize.allCases {
            #expect(FeatureGate.isSizeAvailable(size, unlocked: false) == (size != .large))
            #expect(FeatureGate.isSizeAvailable(size, unlocked: true))
        }
    }

    /// Difficulty is deliberately ungated — a free player can play Hard.
    @Test func difficultyIsNeverPaid() {
        for difficulty in Difficulty.allCases {
            #expect(FeatureGate.isDifficultyAvailable(difficulty, unlocked: false))
        }
    }

    @Test func everyPaidFeatureNeedsTheUnlock() {
        for feature in PaidFeature.allCases {
            #expect(!FeatureGate.isAvailable(feature, unlocked: false))
            #expect(FeatureGate.isAvailable(feature, unlocked: true))
        }
    }

    // MARK: - EntitlementStore cache semantics

    private func scratchDefaults(_ name: String) -> UserDefaults {
        let defaults = UserDefaults(suiteName: "kakuro.tests.\(name)")!
        defaults.removePersistentDomain(forName: "kakuro.tests.\(name)")
        return defaults
    }

    /// The cold-launch flicker test: a paying player must not see locks on the
    /// first frame while `currentEntitlements` is still resolving.
    @MainActor
    @Test func cachedUnlockAppliesSynchronouslyAtInit() {
        let defaults = scratchDefaults("cached")
        defaults.set(true, forKey: "kakuro.entitlement.v1")
        let store = EntitlementStore(userDefaults: defaults,
                                     source: PreviewEntitlementSource(owned: true))
        #expect(store.isUnlocked, "cache must be read before any await")
    }

    @MainActor
    @Test func completedEnumerationDowngradesAndRewritesCache() async {
        let defaults = scratchDefaults("downgrade")
        defaults.set(true, forKey: "kakuro.entitlement.v1")
        let store = EntitlementStore(userDefaults: defaults,
                                     source: PreviewEntitlementSource(owned: false))
        await store.refresh()
        #expect(!store.isUnlocked, "a refund must take the unlock away")
        #expect(!defaults.bool(forKey: "kakuro.entitlement.v1"))
    }

    /// An indeterminate answer must never downgrade somebody who paid.
    ///
    /// This used to be reassuring and hollow: it exercised the stub, while the
    /// production source had no `nil` return at all, so the guard it protects
    /// was dead code on a real device. `productionSourceCanReportIndeterminate`
    /// below is the half that keeps it honest.
    @MainActor
    @Test func indeterminateAnswerKeepsTheCachedUnlock() async {
        let defaults = scratchDefaults("offline")
        defaults.set(true, forKey: "kakuro.entitlement.v1")
        let store = EntitlementStore(userDefaults: defaults,
                                     source: PreviewEntitlementSource(owned: nil))
        await store.refresh()
        #expect(store.isUnlocked, "an indeterminate answer must not revoke the unlock")
        #expect(defaults.bool(forKey: "kakuro.entitlement.v1"))
    }

    /// The shipping source must be able to produce the `nil` the contract
    /// promises. A source that can only ever answer true or false makes the
    /// test above a fiction, which is exactly what shipped in build 1.
    @Test func productionSourceCanReportIndeterminate() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: root.appending(path: "Kakuro/Store/EntitlementStore.swift"),
            encoding: .utf8)
        guard let body = source.range(of: "struct StoreKitEntitlementSource") else {
            Issue.record("could not find the production source"); return
        }
        let production = String(source[body.lowerBound...])
        #expect(production.contains("return nil"),
                "StoreKitEntitlementSource.isOwned has no nil path, so the never-downgrade contract cannot hold on a device")
    }

    @MainActor
    @Test func purchaseIsPickedUpByRefresh() async {
        let defaults = scratchDefaults("purchase")
        let store = EntitlementStore(userDefaults: defaults,
                                     source: PreviewEntitlementSource(owned: true))
        #expect(!store.isUnlocked, "nothing cached yet")
        await store.refresh()
        #expect(store.isUnlocked)
        #expect(defaults.bool(forKey: "kakuro.entitlement.v1"))
    }

    // MARK: - Hint policy

    @MainActor
    private func makeGame(_ puzzle: KakuroPuzzle) -> KakuroGame {
        let logical = LogicalSolver.solve(puzzle)
        return KakuroGame(puzzle: GeneratedPuzzle(
            puzzle: puzzle, difficulty: .easy, techniqueProfile: logical.histogram))
    }

    @MainActor
    @Test func lockedHintNamesNoTechniqueAndCostsNoMastery() {
        let game = makeGame(Fixtures.tiny2x2Unique)
        let mastery = MasteryTracker()
        let hint = HintEngine().hint(for: game, mastery: mastery, policy: .errorsOnly)

        #expect(hint.isLocked)
        #expect(!hint.text.contains(hint.application.technique.displayName),
                "a withheld hint must not give away the technique name")
        // The side effect that would silently damage a player's progress path.
        #expect(mastery.record(for: hint.application.technique).hintedUses == 0)
    }

    @MainActor
    @Test func lockedHintDoesNotEscalate() {
        let game = makeGame(Fixtures.tiny2x2Unique)
        let mastery = MasteryTracker()
        let engine = HintEngine()
        let hint = engine.hint(for: game, mastery: mastery, policy: .errorsOnly)
        let escalated = engine.escalate(hint, for: game, mastery: mastery, policy: .errorsOnly)
        #expect(escalated.level == hint.level, "the ladder is part of the unlock")
        #expect(escalated.isLocked)
    }

    /// Free players still get the error check — that half is not paid.
    @MainActor
    @Test func errorHintsSurviveTheErrorsOnlyPolicy() {
        let game = makeGame(Fixtures.tiny2x2Unique)
        let wrong = game.puzzle.whitePositions.first!
        let solution = game.puzzle.solution(at: wrong)!
        game.selected = wrong
        game.enter(solution == 9 ? 1 : 9)

        let hint = HintEngine().hint(for: game, mastery: MasteryTracker(),
                                     showErrors: true, policy: .errorsOnly)
        #expect(hint.isErrorHint)
        #expect(!hint.isLocked)
    }
}
