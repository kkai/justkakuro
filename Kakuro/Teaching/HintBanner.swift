import SwiftUI

/// The hint surface: a quiet card above the pad. "More" escalates one level;
/// "Apply" executes a resolution-level hint as one undoable move.
struct HintBanner: View {
    let hint: Hint
    let onMore: () -> Void
    let onApply: () -> Void
    let onDismiss: () -> Void
    var onUnlock: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if !hint.isErrorHint, hint.level >= .technique {
                    Text(hint.application.technique.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.indigo)
                        .textCase(.uppercase)
                }
                if hint.isErrorHint {
                    Text("Check your work")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.error)
                        .textCase(.uppercase)
                }
                Spacer()
                // On tvOS this moves into the action row below, so that every
                // control in the banner sits on one horizontal line. Up here it
                // is diagonally above "Tell me more", and the focus engine
                // searches straight lines: pressing left from the cross found
                // nothing and dropped focus back onto the board, which left the
                // hint readable but impossible to escalate or apply.
                #if !os(tvOS)
                dismissButton
                #endif
            }
            Text(hint.text)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                if hint.isLocked {
                    Button(action: onUnlock) {
                        Text("Unlock hints")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.indigo)
                    }
                    .buttonStyle(.kakuro)
                } else if hint.level < .resolution {
                    Button(action: onMore) {
                        Text("Tell me more")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.indigo)
                    }
                    .buttonStyle(.kakuro)
                }
                Spacer()
                if hint.level == .resolution, !hint.isErrorHint {
                    Button(action: onApply) {
                        Text("Apply")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.paper)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Theme.indigo))
                    }
                    .buttonStyle(.kakuro)
                }
                #if os(tvOS)
                dismissButton
                #endif
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        )
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: Metrics.glyph, weight: .semibold))
                .foregroundStyle(Theme.inkSoft)
        }
        .buttonStyle(.kakuro)
        .accessibilityLabel("Dismiss hint")
    }
}
