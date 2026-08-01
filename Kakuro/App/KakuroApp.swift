import SwiftUI

@main
struct KakuroApp: App {
    @State private var progress: ProgressStore
    @State private var mastery: MasteryTracker
    @State private var cache = PuzzleCache()
    @State private var entitlements: EntitlementStore
    @State private var paywall = PaywallPresenter()

    init() {
        let store = ProgressStore()
        _progress = State(initialValue: store)
        _mastery = State(initialValue: MasteryTracker(store: store))
        _entitlements = State(initialValue: Self.makeEntitlementStore())
    }

    /// Real StoreKit, except when capturing App Store screenshots of the paid
    /// tier, which cannot be reached in a simulator without a live purchase.
    ///
    /// Wrapped in `#if DEBUG` deliberately: a launch argument that grants the
    /// unlock must not exist in the binary that ships. `ReleaseBuildTests`
    /// checks the flag string is absent from a Release build.
    private static func makeEntitlementStore() -> EntitlementStore {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains(Self.screenshotUnlockFlag) {
            return EntitlementStore(source: PreviewEntitlementSource(owned: true))
        }
        #endif
        return EntitlementStore()
    }

    static let screenshotUnlockFlag = "-KakuroScreenshotUnlock"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(progress)
                .environment(mastery)
                .environment(cache)
                .environment(entitlements)
                .environment(paywall)
                .onAppear {
                    Haptics.enabled = progress.settings.hapticsEnabled
                }
        }
    }
}
