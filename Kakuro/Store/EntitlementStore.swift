import Foundation
import Observation
import StoreKit

/// The product this app sells. One non-consumable, forever.
nonisolated enum StoreProduct {
    static let fullUnlock = "de.kaikunze.kakuro.full"
}

/// What came back from a purchase attempt.
///
/// `Product.purchase()` has four meaningfully different outcomes and collapsing
/// them into a Bool is how "tapped Buy, nothing happened" bugs get written: a
/// parent-approval request and a cancelled sheet look identical to the caller.
nonisolated enum PurchaseOutcome: Sendable, Equatable {
    case purchased
    /// Ask to Buy: sent for approval. The entitlement arrives later through
    /// `Transaction.updates`, so this is a waiting state rather than a failure.
    case awaitingApproval
    case cancelled
    /// Signed by something other than Apple. Deliberately not finished, per
    /// Apple's guidance, so a later verification can still succeed.
    case unverified
}

nonisolated enum RestoreOutcome: Sendable, Equatable {
    case restored
    /// The sync worked and this Apple Account owns nothing to restore. Silence
    /// here reads exactly like a broken restore button, so it gets said out loud.
    case nothingToRestore
    case cancelled
}

/// The seam between the app and StoreKit. Everything that touches `StoreKit`
/// lives behind this, so the flows can be tested without a store connection.
protocol EntitlementSource: Sendable {
    /// `nil` means *could not determine*, and must never downgrade a cached
    /// entitlement. See `StoreKitEntitlementSource.isOwned` for exactly when
    /// that is returned, because StoreKit does not report it directly.
    func isOwned(_ productID: String) async -> Bool?
    func product(_ productID: String) async -> Product?
    /// Takes the identifier rather than a `Product`, because `Product` can only
    /// be built by StoreKit. A seam that demands one cannot be faked, which is
    /// how every purchase outcome went untested.
    func purchase(_ productID: String) async throws -> PurchaseOutcome
    func restore() async throws
    func transactionUpdates() -> AsyncStream<Void>
}

@Observable @MainActor
final class EntitlementStore {

    enum PurchaseState: Equatable {
        case idle
        case loadingProduct
        case purchasing
        case restoring
        /// Ask to Buy is pending. Not an error, and not done either.
        case awaitingApproval
        /// Something worth saying that is not a failure, such as finding
        /// nothing to restore.
        case note(String)
        case failed(String)

        /// True while a StoreKit operation is in flight. Both buttons key off
        /// this, so a purchase and a restore can never run at once.
        var isBusy: Bool {
            switch self {
            case .loadingProduct, .purchasing, .restoring: true
            default: false
            }
        }
    }

    /// Holds the `Transaction.updates` listener so it dies with the store. A
    /// `deinit` on a `@MainActor` class is nonisolated and cannot touch isolated
    /// state, so ownership lives in this box instead.
    private final class ListenerBox: @unchecked Sendable {
        var task: Task<Void, Never>?
        deinit { task?.cancel() }
    }

    private let defaults: UserDefaults
    private let source: EntitlementSource
    private let listener = ListenerBox()

    private enum Key {
        /// A *display hint* only, so the first frame after a cold launch doesn't
        /// show locks to somebody who has paid. StoreKit remains authoritative:
        /// this is only ever written from a completed entitlement enumeration,
        /// and a completed enumeration returning false (refund, family revoke,
        /// a different Apple Account) clears it.
        ///
        /// Yes, editing the app's plist unlocks the app. For a single $4.99
        /// purchase with no server, that is a better trade than a receipt
        /// validation backend.
        static let unlocked = "kakuro.entitlement.v1"
    }

    private(set) var isUnlocked: Bool
    private(set) var product: Product?
    var purchaseState: PurchaseState = .idle

    init(userDefaults: UserDefaults = .standard,
         source: EntitlementSource = StoreKitEntitlementSource()) {
        self.defaults = userDefaults
        self.source = source
        // Synchronous, so the very first frame is already right.
        self.isUnlocked = userDefaults.bool(forKey: Key.unlocked)

        // Started here rather than in a view's .task: the listener has to be
        // live before any transaction can complete, and view lifecycle is not a
        // guarantee. This is also what delivers an Ask to Buy approved later.
        let stream = source.transactionUpdates()
        listener.task = Task { [weak self] in
            for await _ in stream {
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    /// Re-reads ownership from StoreKit. A `nil` answer leaves the cached value
    /// untouched — see `Key.unlocked`.
    func refresh() async {
        guard let owned = await source.isOwned(StoreProduct.fullUnlock) else { return }
        isUnlocked = owned
        defaults.set(owned, forKey: Key.unlocked)
    }

    /// Clears anything left over from a previous attempt, so an error from one
    /// screen does not greet the player on another.
    func clearTransientState() {
        if !purchaseState.isBusy { purchaseState = .idle }
    }

    func loadProduct() async {
        guard product == nil else { return }
        purchaseState = .loadingProduct
        product = await source.product(StoreProduct.fullUnlock)
        purchaseState = .idle
    }

    func purchase() async {
        guard !purchaseState.isBusy else { return }
        purchaseState = .purchasing            // set first: the button disables on isBusy
        do {
            switch try await source.purchase(StoreProduct.fullUnlock) {
            case .purchased:
                purchaseState = .idle
                await refresh()
            case .awaitingApproval:
                purchaseState = .awaitingApproval
            case .cancelled:
                purchaseState = .idle
            case .unverified:
                purchaseState = .failed(
                    "That purchase could not be verified with the App Store, so nothing has been unlocked. "
                    + "If you were charged, tap Restore purchases.")
            }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    func restore() async {
        guard !purchaseState.isBusy else { return }
        purchaseState = .restoring
        do {
            try await source.restore()
            await refresh()
            purchaseState = isUnlocked
                ? .idle
                : .note("Nothing to restore on this Apple Account. If you bought Just Kakuro with a "
                        + "different account, sign in with that one and try again.")
        } catch let error as StoreKitError where error.isUserCancelled {
            // Dismissing the password prompt is a choice, not a failure.
            purchaseState = .idle
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }
}

private extension StoreKitError {
    var isUserCancelled: Bool {
        if case .userCancelled = self { return true }
        return false
    }
}

/// A fixed answer, for SwiftUI previews and tests.
struct PreviewEntitlementSource: EntitlementSource {
    let owned: Bool?

    init(owned: Bool?) { self.owned = owned }

    func isOwned(_ productID: String) async -> Bool? { owned }
    func product(_ productID: String) async -> Product? { nil }
    func purchase(_ productID: String) async throws -> PurchaseOutcome { .cancelled }
    func restore() async throws {}
    func transactionUpdates() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

/// Raised when the product cannot be fetched, so the player is told the store
/// is unreachable rather than watching the button do nothing.
struct StoreUnavailable: LocalizedError {
    var errorDescription: String? {
        "The store is unavailable right now. Try again in a moment."
    }
}

/// The production source: real StoreKit 2.
struct StoreKitEntitlementSource: EntitlementSource {

    /// Ownership according to StoreKit, or `nil` when the answer cannot be
    /// trusted.
    ///
    /// StoreKit has no "the store is unreachable" signal here:
    /// `Transaction.currentEntitlements` simply yields nothing, which is also
    /// what owning nothing looks like. It is backed by an on-device cache, so an
    /// empty enumeration is nearly always truthful. The one case worth guarding
    /// is an empty enumeration *and* a store that cannot be reached at all,
    /// which together suggest the cache has not been populated rather than that
    /// the player owns nothing. Only then is the cached value left alone.
    ///
    /// An empty enumeration against a reachable store is authoritative, and
    /// downgrading is correct: that is what a refund, a family revoke, or a
    /// different Apple Account looks like.
    func isOwned(_ productID: String) async -> Bool? {
        var sawAnyTransaction = false
        for await result in Transaction.currentEntitlements {
            sawAnyTransaction = true
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == productID, transaction.revocationDate == nil {
                return true
            }
        }
        if !sawAnyTransaction, !(await storeIsReachable(productID)) {
            return nil
        }
        return false
    }

    private func storeIsReachable(_ productID: String) async -> Bool {
        ((try? await Product.products(for: [productID])) != nil)
    }

    func product(_ productID: String) async -> Product? {
        try? await Product.products(for: [productID]).first
    }

    func purchase(_ productID: String) async throws -> PurchaseOutcome {
        guard let product = await product(productID) else {
            throw StoreUnavailable()
        }
        switch try await startPurchase(of: product) {
        case .success(let verification):
            switch verification {
            case .verified(let transaction):
                await transaction.finish()
                return .purchased
            case .unverified:
                // Left unfinished on purpose: StoreKit will offer it again, and
                // a later check may verify it. Finishing here would discard a
                // purchase the player may genuinely have made.
                return .unverified
            }
        case .pending:
            return .awaitingApproval
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// Starts the purchase sheet.
    ///
    /// visionOS does not have the plain `purchase()`: a purchase there is
    /// confirmed in a specific scene, because a Vision Pro can have several of
    /// this app's windows open at once and the system has to know which one the
    /// sheet belongs to. Everywhere else there is exactly one place it could
    /// appear, so the scene is implicit.
    private func startPurchase(of product: Product) async throws -> Product.PurchaseResult {
        #if os(visionOS)
        let scene = await MainActor.run {
            UIApplication.shared.connectedScenes
                .first { $0.activationState == .foregroundActive } as? UIWindowScene
        }
        guard let scene else { throw StoreUnavailable() }
        return try await product.purchase(confirmIn: scene)
        #else
        return try await product.purchase()
        #endif
    }

    func restore() async throws {
        try await AppStore.sync()
    }

    func transactionUpdates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    if case .verified(let transaction) = result {
                        await transaction.finish()
                    }
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
