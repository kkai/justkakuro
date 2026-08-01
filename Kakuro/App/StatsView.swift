import SwiftUI

struct StatsView: View {
    @Environment(ProgressStore.self) private var progress
    @Environment(MasteryTracker.self) private var mastery
    @Environment(EntitlementStore.self) private var entitlements

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            // Covers masteryCard too, which is the mastery-tracking surface.
            // The tracker keeps recording for free players — showing an empty
            // progress path to somebody who just paid would punish the purchase.
            if !entitlements.isUnlocked {
                LockedFeatureView(feature: .stats)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        overviewCard
                        bestTimesCard
                        masteryCard
                    }
                    .padding(20)
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.large)
    }

    private var overviewCard: some View {
        HStack(spacing: 0) {
            stat(value: "\(progress.stats.puzzlesSolved)", label: "solved")
            Divider().padding(.vertical, 8)
            stat(value: formatDuration(progress.stats.totalPlayTime), label: "played")
            Divider().padding(.vertical, 8)
            stat(value: "\(learnedCount)/\(Technique.allCases.count)", label: "techniques")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
    }

    private var learnedCount: Int {
        Technique.allCases.filter { mastery.state(of: $0) == .learned }.count
    }

    private func stat(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Theme.digitFont(size: 24))
                .foregroundStyle(Theme.ink)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.inkSoft)
        }
        .frame(maxWidth: .infinity)
    }

    private var bestTimesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Best times")
                .font(Theme.heading)
                .foregroundStyle(Theme.ink)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    Text("")
                    ForEach(Difficulty.allCases) { difficulty in
                        Text(difficulty.displayName)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.inkSoft)
                            .gridColumnAlignment(.trailing)
                    }
                }
                ForEach(BoardSize.allCases) { size in
                    GridRow {
                        Text(size.displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.ink)
                        ForEach(Difficulty.allCases) { difficulty in
                            Text(progress.bestTime(size: size, difficulty: difficulty)
                                .map(formatTime) ?? "—")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(Theme.inkSoft)
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
    }

    private var masteryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Technique path")
                .font(Theme.heading)
                .foregroundStyle(Theme.ink)
            ForEach(Technique.allCases) { technique in
                let record = mastery.record(for: technique)
                HStack {
                    Text(technique.displayName)
                        .font(.subheadline)
                        .foregroundStyle(record.state == .locked ? Theme.inkSoft : Theme.ink)
                    Spacer()
                    Text(stateLabel(record.state))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(record.state == .learned ? Theme.complete : Theme.inkSoft)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface))
    }

    private func stateLabel(_ state: MasteryTracker.MasteryState) -> String {
        switch state {
        case .locked: "Locked"
        case .introduced: "Introduced"
        case .practicing: "Practicing"
        case .learned: "Learned"
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        TimeFormatting.clock(interval)
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        TimeFormatting.duration(interval)
    }
}

struct SettingsView: View {
    @Environment(ProgressStore.self) private var progress
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(PaywallPresenter.self) private var paywall

    var body: some View {
        @Bindable var progress = progress
        ZStack {
            Theme.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    toggleRow("Auto notes on new puzzles",
                              subtitle: "Fill pencil marks with basic candidates automatically",
                              isOn: $progress.settings.autoNotes)
                    toggleRow("Haptics",
                              subtitle: "Gentle feedback on entries and completions",
                              isOn: $progress.settings.hapticsEnabled)
                    toggleRow("Show errors",
                              subtitle: "Point out contradictions when you ask for a hint",
                              isOn: $progress.settings.showErrors)

                    if !entitlements.isUnlocked {
                        actionRow("Unlock everything",
                                  subtitle: "Every lesson, drill, teaching hints, large boards and stats") {
                            paywall.present(.advancedLessons)
                        }
                    }
                    // Apple requires a restore path for non-consumables, and it
                    // has to be reachable even when the app already believes it
                    // is unlocked.
                    actionRow("Restore purchases",
                              subtitle: restoreSubtitle) {
                        Task { await entitlements.restore() }
                    }
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .onChange(of: progress.settings.hapticsEnabled) { _, enabled in
            Haptics.enabled = enabled
        }
    }

    /// Says which of restoring, restored, found-nothing and failed happened.
    /// Silence after a restore is indistinguishable from a broken button.
    private var restoreSubtitle: String {
        switch entitlements.purchaseState {
        case .restoring: "Checking with the App Store…"
        case .note(let message): message
        case .failed(let message): message
        default: entitlements.isUnlocked
            ? "The full game is unlocked on this Apple Account"
            : "Already bought it? Bring it back on this device"
        }
    }

    private func actionRow(_ title: String, subtitle: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.indigo)
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSoft)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
        }
        .buttonStyle(.plain)
    }

    private func toggleRow(_ title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(Theme.inkSoft)
            }
        }
        .tint(Theme.indigo)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
    }
}
