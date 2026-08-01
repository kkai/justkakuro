import SwiftUI

@main
struct KakuroApp: App {
    @State private var progress: ProgressStore
    @State private var mastery: MasteryTracker
    @State private var cache = PuzzleCache()
    @State private var entitlements = EntitlementStore()
    @State private var paywall = PaywallPresenter()

    init() {
        let store = ProgressStore()
        _progress = State(initialValue: store)
        _mastery = State(initialValue: MasteryTracker(store: store))
    }

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
