import SwiftUI

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

    /// Sheets are half-height cards on iOS and free-floating resizable panels on
    /// macOS, where `presentationDetents` does not exist. A minimum frame is the
    /// closest equivalent: it stops the panel opening at its compressed size.
    @ViewBuilder
    func mediumSheet() -> some View {
        #if os(iOS)
        presentationDetents([.medium])
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
struct SheetCloseButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.inkSoft)
                .padding(9)
                .background(Circle().fill(Theme.surface))
        }
        .buttonStyle(.plain)
        // Escape, which is where a Mac user reaches first.
        .keyboardShortcut(.cancelAction)
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
