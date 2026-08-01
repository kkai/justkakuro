import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// A light/dark colour value, held as plain components rather than a `UIColor`
/// or `NSColor`.
///
/// This is what lets the provider closure in `Theme.dynamic(light:dark:)` stay
/// `@Sendable` on both platforms: it captures only these, and whether a given
/// SDK declares its platform colour type `Sendable` stops mattering. See the
/// note on `Theme` for why that closure's annotations are load-bearing.
nonisolated struct ThemeRGBA: Sendable {
    let red, green, blue, alpha: CGFloat

    static let white = ThemeRGBA(red: 1, green: 1, blue: 1, alpha: 1)
}

#if canImport(UIKit)
private extension UIColor {
    convenience init(_ c: ThemeRGBA) {
        self.init(red: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }
}
#else
private extension NSColor {
    /// `srgbRed:` rather than `red:`, so the components land in the same colour
    /// space UIKit puts them in and the two platforms render identically.
    convenience init(_ c: ThemeRGBA) {
        self.init(srgbRed: c.red, green: c.green, blue: c.blue, alpha: c.alpha)
    }
}
#endif

/// Semantic color and type tokens. Ink-and-indigo on washi paper: Kakuro is a
/// newspaper puzzle, so numerals are serif (New York), chrome is quiet, and the
/// diagonal of the clue cell is the app's signature motif.
///
/// `nonisolated` is load-bearing, not tidiness. The project builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so without it `Theme` — and the
/// provider closure in `dynamic(light:dark:)` — is implicitly `@MainActor`.
/// UIKit imports `-initWithDynamicProvider:` without `NS_SWIFT_SENDABLE`, so the
/// closure inherits that isolation and Swift 6 emits an executor assertion in
/// its prologue. UIKit resolves dynamic colors from SwiftUI's
/// `com.apple.SwiftUI.AsyncRenderer` thread, which trips the assertion and traps
/// (EXC_BREAKPOINT). It fired intermittently — anywhere, including an idle Home
/// screen — because whether a given resolve lands off-main is a race.
/// Guarded by ThemeIsolationTests.
nonisolated enum Theme {

    // MARK: - Colors (light / dark pairs)

    /// Cool washi paper / near-black ink field.
    static let paper = dynamic(light: ThemeRGBA(red: 0.949, green: 0.953, blue: 0.933, alpha: 1),
                               dark: ThemeRGBA(red: 0.078, green: 0.086, blue: 0.102, alpha: 1))
    /// Card and cell surfaces. In dark mode this carries the whole "playable vs
    /// blocked" read, so it sits well above `paper` and far above `block` — at
    /// near-equal darkness the grid turns into an unreadable field.
    static let surface = dynamic(light: .white,
                                 dark: ThemeRGBA(red: 0.224, green: 0.239, blue: 0.278, alpha: 1))
    /// Graphite ink for entered digits and primary text.
    static let ink = dynamic(light: ThemeRGBA(red: 0.133, green: 0.149, blue: 0.169, alpha: 1),
                             dark: ThemeRGBA(red: 0.910, green: 0.914, blue: 0.894, alpha: 1))
    /// Secondary text, notes, quiet labels.
    static let inkSoft = dynamic(light: ThemeRGBA(red: 0.133, green: 0.149, blue: 0.169, alpha: 0.55),
                                 dark: ThemeRGBA(red: 0.910, green: 0.914, blue: 0.894, alpha: 0.55))
    /// Block cells: deep indigo-charcoal, the "filled ink" of the grid.
    static let block = dynamic(light: ThemeRGBA(red: 0.169, green: 0.196, blue: 0.251, alpha: 1),
                               dark: ThemeRGBA(red: 0.035, green: 0.041, blue: 0.055, alpha: 1))
    /// Clue numerals on block cells.
    static let clueText = dynamic(light: ThemeRGBA(red: 0.949, green: 0.953, blue: 0.933, alpha: 0.92),
                                  dark: ThemeRGBA(red: 0.910, green: 0.914, blue: 0.894, alpha: 0.80))
    /// Indigo: selection, interactive tint, focus.
    static let indigo = dynamic(light: ThemeRGBA(red: 0.231, green: 0.357, blue: 0.647, alpha: 1),
                                dark: ThemeRGBA(red: 0.486, green: 0.592, blue: 0.847, alpha: 1))
    /// Soft indigo wash for selected/related cells.
    static let indigoWash = dynamic(light: ThemeRGBA(red: 0.231, green: 0.357, blue: 0.647, alpha: 0.14),
                                    dark: ThemeRGBA(red: 0.486, green: 0.592, blue: 0.847, alpha: 0.20))
    /// Seal red, reserved for errors only.
    static let error = dynamic(light: ThemeRGBA(red: 0.769, green: 0.263, blue: 0.220, alpha: 1),
                               dark: ThemeRGBA(red: 0.898, green: 0.451, blue: 0.404, alpha: 1))
    /// Success/completion sweep tint.
    static let complete = dynamic(light: ThemeRGBA(red: 0.282, green: 0.522, blue: 0.416, alpha: 1),
                                  dark: ThemeRGBA(red: 0.463, green: 0.702, blue: 0.588, alpha: 1))
    /// Hairlines and grid lines.
    static let hairline = dynamic(light: ThemeRGBA(red: 0.133, green: 0.149, blue: 0.169, alpha: 0.16),
                                  dark: ThemeRGBA(red: 0.910, green: 0.914, blue: 0.894, alpha: 0.14))

    /// The closure is *also* explicitly `@Sendable`. That is redundant while
    /// `Theme` is `nonisolated` — a `@Sendable` closure never inherits actor
    /// isolation — and deliberately so: either annotation alone prevents the
    /// executor-assertion prologue, so losing one does not silently bring the
    /// trap back. `dynamicProvider:` is spelled out rather than the trailing
    /// closure `UIColor { … }` so the dangerous API stays greppable.
    ///
    /// It captures `ThemeRGBA` values rather than platform colour objects, which
    /// is the third layer of the same protection: components are plainly
    /// `Sendable`, so the annotation above cannot be invalidated by whatever the
    /// SDK does or does not declare about `UIColor` and `NSColor`.
    private static func dynamic(light: ThemeRGBA, dark: ThemeRGBA) -> Color {
        #if canImport(UIKit)
        Color(UIColor(dynamicProvider: { @Sendable trait in
            UIColor(trait.userInterfaceStyle == .dark ? dark : light)
        }))
        #else
        // AppKit resolves against an NSAppearance rather than a trait
        // collection, and `bestMatch` is the documented way to ask a possibly
        // vibrant or accessibility appearance which of the two it counts as.
        Color(NSColor(name: nil, dynamicProvider: { @Sendable appearance in
            NSColor(appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light)
        }))
        #endif
    }

    // MARK: - Type

    /// Entered digits: serif, the newspaper numeral.
    static func digitFont(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    /// Clue numerals on block cells.
    static func clueFont(size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .serif)
    }

    /// Pencil notes.
    static func noteFont(size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .default)
    }

    /// Display face for titles — serif carries the wordmark.
    static let title = Font.system(.largeTitle, design: .serif, weight: .bold)
    static let heading = Font.system(.title2, design: .serif, weight: .semibold)
}
