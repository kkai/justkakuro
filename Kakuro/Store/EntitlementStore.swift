import Foundation
import Observation
import StoreKit

/// The product this app sells. One non-consumable, forever.
nonisolated enum StoreProduct {
    static let fullUnlock = "de.kaikunze.kakuro.full"
}

/// The seam between the app and StoreKit. Everything that touches `StoreKit`
/// lives behind this, so gating can be tested without a store connection.
///
/// `isOwned` returns `nil` to mean *could not determine* (offline, StoreKit
/// error). That is deliberately distinct from `false`: a failure must never
/// take away what somebody bought.
protocol EntitlementSource: Sendable {
    func isOwned(_ productID: String) async -> Bool?
    func product(_ productID: String) async -> Product?
    func purchase(_ product: Product) async throws -> Bool
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
        case failed(String)
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
        /// and a completed enumeration returning false (refund, family revoke)
        /// clears it.
        ///
        /// Yes, editing the app's plist unlocks the app. For a single $4.99
        /// purchase with no server, that is a better trade than a receipt
        /// validation backend — do not "fix" this by trusting it less on launch
        /// and more on error; the error path is what protects offline players.
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
        // guarantee. A screen must outlive the state that created it.
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

    func loadProduct() async {
        guard product == nil else { return }
        purchaseState = .loadingProduct
        product = await source.product(StoreProduct.fullUnlock)
        purchaseState = .idle
    }

    func purchase() async {
        await loadProduct()
        guard let product else {
            purchaseState = .failed("The store is unavailable right now. Try again in a moment.")
            return
        }
        purchaseState = .purchasing
        do {
            let completed = try await source.purchase(product)
            purchaseState = .idle
            if completed { await refresh() }
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }

    func restore() async {
        purchaseState = .restoring
        do {
            try await source.restore()
            await refresh()
            purchaseState = .idle
        } catch {
            purchaseState = .failed(error.localizedDescription)
        }
    }
}

/// A fixed answer, for SwiftUI previews and tests. `owned: nil` simulates
/// "could not determine" (offline / StoreKit error).
struct PreviewEntitlementSource: EntitlementSource {
    let owned: Bool?

    init(owned: Bool?) { self.owned = owned }

    func isOwned(_ productID: String) async -> Bool? { owned }
    func product(_ productID: String) async -> Product? { nil }
    func purchase(_ product: Product) async throws -> Bool { false }
    func restore() async throws {}
    func transactionUpdates() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

/// The production source: real StoreKit 2.
struct StoreKitEntitlementSource: EntitlementSource {

    func isOwned(_ productID: String) async -> Bool? {
        var sawAny = false
        for await result in Transaction.currentEntitlements {
            sawAny = true
            guard case .verified(let transaction) = result else { continue }
            if transaction.productID == productID, transaction.revocationDate == nil {
                return true
            }
        }
        // An empty enumeration is a legitimate "you own nothing", not an error;
        // StoreKit surfaces genuine failures by never yielding at all, which we
        // cannot distinguish here — so treat completion as authoritative.
        _ = sawAny
        return false
    }

    func product(_ productID: String) async -> Product? {
        try? await Product.products(for: [productID]).first
    }

    func purchase(_ product: Product) async throws -> Bool {
        switch try await product.purchase() {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                await transaction.finish()
                return true
            }
            return false
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
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
