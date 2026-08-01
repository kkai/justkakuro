import SwiftUI

/// The wait while a board is generated.
///
/// Escalates rather than showing one indeterminate spinner forever: most boards
/// arrive before anything is drawn at all, and the ones that don't deserve an
/// honest explanation and a way out.
///
/// The bar tracks **fraction of the deterministic search budget spent**, which
/// has one genuinely useful property: exhausting the budget is not failure — it
/// routes to the instant baked fallback. So the bar reaching the end really
/// does coincide with a board appearing. What it is *not* is linear in wall
/// time; a search can succeed at 5% or grind to 90%. Hence no percentage text.
struct PuzzleLoadingView: View {
    let fraction: Double
    let startedAt: Date
    let onCancel: () -> Void

    private enum Stage {
        case silent, indeterminate, determinate, slow

        init(elapsed: TimeInterval) {
            switch elapsed {
            case ..<0.3: self = .silent
            case ..<1.2: self = .indeterminate
            case ..<5: self = .determinate
            default: self = .slow
            }
        }
    }

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 0.1)) { context in
            let stage = Stage(elapsed: context.date.timeIntervalSince(startedAt))
            ZStack {
                Theme.paper.ignoresSafeArea()
                switch stage {
                case .silent:
                    // A cached board resolves in one hop. A spinner that flashes
                    // for two frames reads as jank, so draw nothing.
                    Color.clear
                case .indeterminate:
                    VStack(spacing: 12) {
                        ProgressView()
                        caption("Preparing a fresh puzzle…")
                    }
                case .determinate, .slow:
                    VStack(spacing: 16) {
                        // Capped below 1 until the board actually arrives — a bar
                        // that sits at 99% is the exact failure to avoid.
                        ProgressView(value: min(fraction, 0.95))
                            .progressViewStyle(.linear)
                            .tint(Theme.indigo)
                            .frame(maxWidth: 260)
                        caption(stage == .slow
                                ? "Big boards take longer. This one is a stubborn build."
                                : "Searching for a board with exactly one solution…")
                        Button("Cancel", action: onCancel)
                            .font(.subheadline.weight(.medium))
                            .tint(Theme.indigo)
                            .padding(.top, 4)
                    }
                    .padding(32)
                }
            }
            .animation(Motion.overlay, value: stage)
            // `.combine` would fold the Cancel button into one label and drop
            // its text, leaving a VoiceOver user with no announced way out of a
            // build that can run for seconds. `.contain` keeps it focusable.
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Building your puzzle")
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(Theme.inkSoft)
            .multilineTextAlignment(.center)
    }
}
