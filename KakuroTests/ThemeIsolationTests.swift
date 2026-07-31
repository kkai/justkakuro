import Foundation
import SwiftUI
import Testing
import UIKit
@testable import Kakuro

// MARK: - Compile-time guard
//
// These helpers are `nonisolated` and synchronous. If `Theme` or `Motion` ever
// loses `nonisolated` and falls back to the project's MainActor default, every
// reference below becomes
//     "main actor-isolated static property 'x' can not be referenced from a
//      nonisolated context"
// and THE TEST TARGET FAILS TO BUILD. That is deliberate: the build breaks
// before the runtime guard below gets a chance to take the whole test runner
// down with a SIGTRAP.
//
// `nonisolated` on these functions is not optional. KakuroTests inherits
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor from the project, so an unannotated
// helper would itself be MainActor-isolated and this guard would silently pass
// forever.

private nonisolated func nonisolatedThemeColors() -> [Color] {
    [Theme.paper, Theme.surface, Theme.ink, Theme.inkSoft, Theme.block,
     Theme.clueText, Theme.indigo, Theme.indigoWash, Theme.error,
     Theme.complete, Theme.hairline]
}

private nonisolated func nonisolatedThemeFonts() -> [Font] {
    [Theme.title, Theme.heading,
     Theme.digitFont(size: 12), Theme.clueFont(size: 12), Theme.noteFont(size: 12)]
}

private nonisolated func nonisolatedMotionTokens() -> [Animation] {
    [Motion.digitEntry, Motion.noteFlip, Motion.selection, Motion.runComplete,
     Motion.boardEntrance, Motion.hintPulse, Motion.overlay]
}

/// Marks the main queue so the runtime guard can prove it ran off it.
private nonisolated let mainQueueKey: DispatchSpecificKey<Bool> = {
    let key = DispatchSpecificKey<Bool>()
    DispatchQueue.main.setSpecific(key: key, value: true)
    return key
}()

/// Component extraction, so comparison does not depend on `UIColor.isEqual`.
private nonisolated func rgba(_ color: UIColor) -> [CGFloat] {
    var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    color.getRed(&r, green: &g, blue: &b, alpha: &a)
    return [r, g, b, a]
}

@Suite struct ThemeIsolationTests {

    /// Keeps the helpers above alive (an unused `nonisolated` function would be
    /// easy to delete, taking the compile-time guard with it) and keeps their
    /// token lists in sync with Theme/Motion.
    @Test func designTokensAreReachableFromANonisolatedContext() {
        #expect(nonisolatedThemeColors().count == 11)
        #expect(nonisolatedThemeFonts().count == 5)
        #expect(nonisolatedMotionTokens().count == 7)
        #expect(Motion.runCompleteStagger > 0)
        #expect(Motion.boardEntranceStagger > 0)
    }

    /// Runtime guard — backstop for the compile-time one.
    ///
    /// Resolves every Theme color off the main thread, in both trait styles.
    /// This is exactly what UIKit does from `com.apple.SwiftUI.AsyncRenderer`.
    /// If a Theme dynamic-color provider ever becomes actor-isolated again this
    /// does NOT fail politely: it traps (EXC_BREAKPOINT) and takes the whole
    /// test runner with it. That is the intended signal — the shipped app did
    /// exactly that, intermittently, even sitting idle on the Home screen.
    @Test func dynamicColorsResolveOffTheMainThread() async {
        let tokens: [(String, Color)] = [
            ("paper", Theme.paper), ("surface", Theme.surface), ("ink", Theme.ink),
            ("inkSoft", Theme.inkSoft), ("block", Theme.block),
            ("clueText", Theme.clueText), ("indigo", Theme.indigo),
            ("indigoWash", Theme.indigoWash), ("error", Theme.error),
            ("complete", Theme.complete), ("hairline", Theme.hairline),
        ]

        // No #expect inside the detached task: Swift Testing tracks the current
        // test in a task-local, which Task.detached does not inherit, so issues
        // recorded in there would be unattributable. Return data, assert outside.
        let result = await Task.detached { () -> (onMain: Bool, differing: [String]) in
            let light = UITraitCollection(userInterfaceStyle: .light)
            let dark = UITraitCollection(userInterfaceStyle: .dark)
            var differing: [String] = []
            for (name, color) in tokens {
                let ui = UIColor(color)
                if rgba(ui.resolvedColor(with: light)) != rgba(ui.resolvedColor(with: dark)) {
                    differing.append(name)
                }
            }
            // `Thread.isMainThread` is unavailable from async contexts, so ask
            // dispatch directly whether we are on the main queue.
            let onMain = DispatchQueue.getSpecific(key: mainQueueKey) != nil
            return (onMain, differing)
        }.value

        #expect(!result.onMain, "guard is meaningless if this ran on the main thread")
        // If a token resolves identically in both styles the provider was never
        // really exercised, and this guard has quietly become a no-op.
        let inert = Set(tokens.map(\.0)).subtracting(result.differing).sorted()
        #expect(inert.isEmpty,
                "these tokens resolved identically in light and dark, so the dynamic provider was not exercised: \(inert)")
    }

    /// Catches the *class* of bug, which neither guard above can: a second
    /// `UIColor` dynamic provider added inside some other, MainActor-isolated
    /// type. Such a closure is invoked from SwiftUI's render thread and traps
    /// under Swift 6 executor checking.
    @Test func dynamicColorProvidersLiveOnlyInNonisolatedTheme() throws {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // KakuroTests
            .deletingLastPathComponent()   // kakuro
            .appendingPathComponent("Kakuro")

        var offenders: Set<String> = []
        var themeSource = ""
        let files = FileManager.default.enumerator(at: sourceRoot,
                                                   includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            if text.contains("dynamicProvider") || text.contains("UIColor {") {
                offenders.insert(url.lastPathComponent)
            }
            if url.lastPathComponent == "Theme.swift" { themeSource = text }
        }

        #expect(offenders == ["Theme.swift"],
                "UIColor dynamic providers must live only in the nonisolated Theme: \(offenders.sorted())")
        #expect(themeSource.contains("nonisolated enum Theme"),
                "Theme must stay nonisolated or its color provider traps on the render thread")
    }
}
