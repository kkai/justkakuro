import Foundation
import Testing
import StoreKit
@testable import Kakuro

/// The purchase and restore surface had no coverage at all, which is how four
/// silent no-ops survived. The seam returns an outcome rather than a Bool
/// precisely so these cases can be expressed here.
@MainActor
@Suite struct PurchaseFlowTests {

    /// Scriptable stand-in for StoreKit.
    private final class FakeSource: EntitlementSource, @unchecked Sendable {
        var owned: Bool?
        var purchaseResult: Result<PurchaseOutcome, Error> = .success(.cancelled)
        var restoreError: Error?
        private(set) var purchaseCalls = 0
        private(set) var restoreCalls = 0
        /// Lets a test observe the state while an operation is in flight.
        var duringPurchase: (@MainActor () -> Void)?

        init(owned: Bool? = false) { self.owned = owned }

        func isOwned(_ productID: String) async -> Bool? { owned }
        func product(_ productID: String) async -> Product? { nil }

        func purchase(_ productID: String) async throws -> PurchaseOutcome {
            purchaseCalls += 1
            if let hook = duringPurchase { await MainActor.run { hook() } }
            return try purchaseResult.get()
        }

        func restore() async throws {
            restoreCalls += 1
            if let restoreError { throw restoreError }
        }

        func transactionUpdates() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
    }

    private func scratch(_ name: String) -> UserDefaults {
        let suite = "kakuro.purchase.\(name).\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    private func store(_ source: FakeSource, _ name: String = "s") -> EntitlementStore {
        EntitlementStore(userDefaults: scratch(name), source: source)
    }

    // MARK: - Purchase outcomes

    /// Ask to Buy used to be indistinguishable from a cancelled sheet: the
    /// paywall simply went back to an enabled buy button and said nothing.
    @Test func askToBuyTellsThePlayerItIsWaiting() async {
        let fake = FakeSource()
        fake.purchaseResult = .success(.awaitingApproval)
        let s = store(fake, "pending")
        await s.purchase()
        #expect(s.purchaseState == .awaitingApproval)
        #expect(!s.isUnlocked, "approval has not arrived yet")
    }

    /// The player was charged. Saying nothing is the worst possible response.
    @Test func unverifiedPurchaseSurfacesAnErrorMentioningRestore() async {
        let fake = FakeSource()
        fake.purchaseResult = .success(.unverified)
        let s = store(fake, "unverified")
        await s.purchase()
        guard case .failed(let message) = s.purchaseState else {
            Issue.record("expected a failure, got \(s.purchaseState)"); return
        }
        #expect(message.lowercased().contains("restore"),
                "an unverified purchase must point at Restore: \(message)")
        #expect(!s.isUnlocked)
    }

    /// Cancelling is a choice. It must not leave an error on screen.
    @Test func cancellingAPurchaseSaysNothing() async {
        let fake = FakeSource()
        fake.purchaseResult = .success(.cancelled)
        let s = store(fake, "cancel")
        await s.purchase()
        #expect(s.purchaseState == .idle)
    }

    @Test func successfulPurchaseUnlocks() async {
        let fake = FakeSource(owned: false)
        fake.purchaseResult = .success(.purchased)
        fake.duringPurchase = { fake.owned = true }   // StoreKit now reports ownership
        let s = store(fake, "buy")
        await s.purchase()
        #expect(s.purchaseState == .idle)
        #expect(s.isUnlocked)
    }

    @Test func aThrownPurchaseShowsTheError() async {
        struct Boom: LocalizedError { var errorDescription: String? { "the network went away" } }
        let fake = FakeSource()
        fake.purchaseResult = .failure(Boom())
        let s = store(fake, "throw")
        await s.purchase()
        guard case .failed(let m) = s.purchaseState else {
            Issue.record("expected failure"); return
        }
        #expect(m.contains("network"))
    }

    // MARK: - The busy invariant

    /// One shared state drives both buttons, so neither can start on top of the
    /// other. Previously the buy button was live during loadProduct.
    @Test func aSecondOperationIsRefusedWhileOneIsInFlight() async {
        let fake = FakeSource()
        fake.purchaseResult = .success(.cancelled)
        let s = store(fake, "busy")
        fake.duringPurchase = {
            #expect(s.purchaseState.isBusy, "state must read busy while purchasing")
            Task { await s.restore() }   // must be refused
        }
        await s.purchase()
        #expect(fake.restoreCalls == 0, "a restore started during a purchase")
    }

    @Test func busyIsFalseWhenNothingIsHappening() {
        for state in [EntitlementStore.PurchaseState.idle, .awaitingApproval,
                      .note("x"), .failed("y")] {
            #expect(!state.isBusy, "\(state) should not read as busy")
        }
        for state in [EntitlementStore.PurchaseState.loadingProduct, .purchasing, .restoring] {
            #expect(state.isBusy, "\(state) should read as busy")
        }
    }

    // MARK: - Restore, all three outcomes

    @Test func restoringSomethingUnlocksAndSaysNothingExtra() async {
        let fake = FakeSource(owned: false)
        let s = store(fake, "restore-ok")
        fake.owned = true
        await s.restore()
        #expect(s.isUnlocked)
        #expect(s.purchaseState == .idle)
    }

    /// The App Review scenario: a reviewer taps Restore on a fresh account and
    /// must not be met with silence.
    @Test func restoringNothingSaysSo() async {
        let fake = FakeSource(owned: false)
        let s = store(fake, "restore-empty")
        await s.restore()
        #expect(!s.isUnlocked)
        guard case .note(let message) = s.purchaseState else {
            Issue.record("expected a note, got \(s.purchaseState)"); return
        }
        #expect(message.lowercased().contains("nothing to restore"))
    }

    /// Dismissing the App Store password prompt is not a failure.
    @Test func cancellingTheRestorePromptIsNotAnError() async {
        let fake = FakeSource(owned: false)
        fake.restoreError = StoreKitError.userCancelled
        let s = store(fake, "restore-cancel")
        await s.restore()
        #expect(s.purchaseState == .idle, "user cancellation must not read as an error")
    }

    @Test func aFailedRestoreShowsTheError() async {
        struct Boom: LocalizedError { var errorDescription: String? { "store unreachable" } }
        let fake = FakeSource(owned: false)
        fake.restoreError = Boom()
        let s = store(fake, "restore-fail")
        await s.restore()
        guard case .failed(let m) = s.purchaseState else {
            Issue.record("expected failure"); return
        }
        #expect(m.contains("unreachable"))
    }

    // MARK: - Stale state

    /// An error raised on one screen used to greet the player on another,
    /// because the state lives on an app-lifetime object.
    @Test func transientStateIsClearedButNotWhileBusy() async {
        let fake = FakeSource()
        let s = store(fake, "clear")
        s.purchaseState = .failed("something from another screen")
        s.clearTransientState()
        #expect(s.purchaseState == .idle)

        s.purchaseState = .purchasing
        s.clearTransientState()
        #expect(s.purchaseState == .purchasing, "clearing must not interrupt work in flight")
    }
}
