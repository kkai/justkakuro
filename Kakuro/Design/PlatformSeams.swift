import SwiftUI

/// Sizes that differ because the screen is a different distance from the eye.
///
/// A phone is held at arm's length and a Mac window sits on a desk; a television
/// is across the room. Everything here is the same on iOS and macOS and larger on
/// tvOS, so the difference lives in one place rather than in fifty call sites.
nonisolated enum Metrics {
    #if os(tvOS)
    /// Small symbols: chevrons, close crosses, list badges. At 12pt these were
    /// invisible from a sofa.
    static let glyph: CGFloat = 26
    /// Reading column. 560 is 29% of a 1920pt screen, which reads as a narrow
    /// strip with two empty thirds beside it.
    static let column: CGFloat = 1100
    /// Board cell ceiling. The canvas is 1080pt tall, so a 9-row board can carry
    /// far more than the 88 a phone needs.
    static let cellCap: CGFloat = 120
    /// The selected-cell ring. On tvOS it is the cursor, so it has to read from
    /// the sofa rather than sit as a hairline.
    static let selectionRing: CGFloat = 6
    /// Wordmark candidates, largest first, for the `ViewThatFits` lockup. A
    /// 44pt title is a reasonable phone banner and a postage stamp on a 1920pt
    /// screen.
    static let wordmark: [CGFloat] = [120, 96, 76]
    /// Segmented pickers size to their content on tvOS. Stretched to the full
    /// column they became 300pt-wide segments, which is neither readable nor
    /// remotely idiomatic.
    static let stretchesSegments = false
    #else
    static let glyph: CGFloat = 13
    static let column: CGFloat = 560
    static let cellCap: CGFloat = 88
    static let selectionRing: CGFloat = 2
    static let wordmark: [CGFloat] = [44, 38, 32]
    static let stretchesSegments = true
    #endif
}

/// The app's button style everywhere.
///
/// On iOS and macOS this is `.plain`: a custom style already replaces the system
/// chrome, and nothing is applied unless the button is focused, which on those
/// platforms only happens with a hardware keyboard.
///
/// tvOS is why it exists. `.plain` there strips the system focus effect, so all
/// nineteen buttons in the app were focusable and looked identical whether
/// focused or not. On a remote, where focus is the only cursor there is, that is
/// unusable.
struct KakuroButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        FocusAware(configuration: configuration)
    }

    private struct FocusAware: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                // Brightness and a shadow, with no scaling and no outline.
                //
                // Two earlier attempts were worse. A fixed-radius ring fitted
                // none of the shapes it landed on, since the cards are radius 16
                // and the Play bar 12, so it read as a smear overhanging the
                // edges. Scaling then broke the full-width controls: Play fills
                // its card, so growing it 5% pushed it out past both sides of
                // the card containing it.
                //
                // Brightness borrows no geometry at all, so it cannot disagree
                // with the shape underneath, and on a television a step this
                // size is unmistakable from across the room.
                .brightness(isFocused ? 0.18 : 0)
                .shadow(color: .black.opacity(isFocused ? 0.55 : 0),
                        radius: isFocused ? 20 : 0, y: isFocused ? 8 : 0)
                .animation(Motion.selection, value: isFocused)
        }
    }
}

extension ButtonStyle where Self == KakuroButtonStyle {
    static var kakuro: KakuroButtonStyle { KakuroButtonStyle() }
}

/// Where SwiftUI's navigation and presentation API differs between iOS and
/// macOS. Collected here so the `#if` count stays at one per concern instead of
/// one per call site, and so adding a screen means picking a seam rather than
/// remembering which modifiers do not exist on the Mac.

/// How a screen wants its navigation title sized.
///
/// macOS has no equivalent of `navigationBarTitleDisplayMode`: a window title is
/// a window title. The enum survives anyway so the iOS intent stays readable at
/// the call site rather than dissolving into a bare `#if`.
enum NavigationTitleDisplay {
    case large
    case inline
}

extension View {
    @ViewBuilder
    func navigationTitleDisplay(_ display: NavigationTitleDisplay) -> some View {
        #if os(iOS)
        switch display {
        case .large: navigationBarTitleDisplayMode(.large)
        case .inline: navigationBarTitleDisplayMode(.inline)
        }
        #else
        self
        #endif
    }

    /// Sheets are half-height cards on iOS, free-floating resizable panels on
    /// macOS, and always full screen on tvOS.
    ///
    /// macOS has no `presentationDetents`, so a minimum frame is the closest
    /// equivalent: it stops the panel opening at its compressed size. tvOS gets
    /// neither. Sizing a tvOS sheet would leave a 460pt island marooned in a
    /// 1920pt field, so it takes the full screen it was always going to get.
    @ViewBuilder
    func mediumSheet() -> some View {
        #if os(iOS)
        presentationDetents([.medium])
        #elseif os(tvOS)
        self
        #else
        frame(minWidth: 460, minHeight: 420)
        #endif
    }
}

/// An explicit way out of a sheet.
///
/// iOS lets you drag a sheet away, so sheets here were built without one. macOS
/// has no such gesture, and a SwiftUI sheet is modal: the first Mac build put
/// the paywall on screen with no exit, which also swallowed Quit and left the
/// app killable only from the outside. Any sheet without its own Done button
/// needs this.
/// On tvOS the Menu button already dismisses a sheet, and `keyboardShortcut` does
/// not exist there at all, so the shortcut is iOS and macOS only.
struct SheetCloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if os(tvOS)
        button
        #else
        // Escape, which is where a Mac user reaches first.
        button.keyboardShortcut(.cancelAction)
        #endif
    }

    private var button: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: Metrics.glyph, weight: .bold))
                .foregroundStyle(Theme.inkSoft)
                .padding(Metrics.glyph * 0.75)
                .background(Circle().fill(Theme.surface))
        }
        .buttonStyle(.kakuro)
        .accessibilityLabel("Close")
    }
}

extension ToolbarItemPlacement {
    /// Trailing end of the navigation bar on iOS, and the leading edge of the
    /// window toolbar's action area on macOS, which is where a Mac user looks
    /// for a screen's own controls.
    static var primaryTrailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}
