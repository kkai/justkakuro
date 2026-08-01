import Foundation
import Observation

/// Which feature the player just bumped into, so the sheet can lead with it.
struct PaywallContext: Identifiable, Equatable {
    let feature: PaidFeature
    var id: String { feature.rawValue }
}

/// Owns paywall presentation for the whole app. One sheet at the root beats
/// five copies scattered through the view tree, and gives one place to hang a
/// purchase celebration later. A service, like `PuzzleCache` — not a ViewModel.
@Observable @MainActor
final class PaywallPresenter {
    private(set) var context: PaywallContext?

    func present(_ feature: PaidFeature) {
        context = PaywallContext(feature: feature)
    }

    func dismiss() {
        context = nil
    }
}
