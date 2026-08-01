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
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.inkSoft)
                }
                .accessibilityLabel("Dismiss hint")
            }
            Text(hint.text)
                .font(.subheadline)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                if hint.isLocked {
                    Button(action: onUnlock) {
                        Text("Unlock hints")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.indigo)
                    }
                } else if hint.level < .resolution {
                    Button(action: onMore) {
                        Text("Tell me more")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.indigo)
                    }
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
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
        )
    }
}
