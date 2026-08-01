import SwiftUI

/// The curriculum as a progress path: rules first, then one lesson per
/// technique, unlocking in order.
struct LearnMenuView: View {
    @Binding var path: [Route]
    @Environment(MasteryTracker.self) private var mastery
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(PaywallPresenter.self) private var paywall

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(TutorialPuzzles.lessonInfos) { info in
                        lessonRow(info)
                    }
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Learn")
        .navigationTitleDisplay(.large)
    }

    private func lessonRow(_ info: TutorialPuzzles.LessonInfo) -> some View {
        let state = info.technique.map { mastery.state(of: $0) } ?? .learned
        // Two different locks. Mastery-locked rows are genuinely unreachable, so
        // they stay disabled. Paywalled rows stay tappable — a dead row neither
        // teaches nor sells.
        let masteryLocked = state == .locked
        let paywalled = !FeatureGate.isLessonAvailable(info.technique,
                                                       unlocked: entitlements.isUnlocked)
        let dimmed = masteryLocked || paywalled
        return Button {
            if paywalled {
                paywall.present(.advancedLessons)
            } else {
                path.append(.tutorial(info.technique))
            }
        } label: {
            HStack(spacing: 14) {
                stateBadge(state, isRules: info.technique == nil, paywalled: paywalled)
                VStack(alignment: .leading, spacing: 3) {
                    Text(info.title)
                        .font(.headline)
                        .foregroundStyle(dimmed ? Theme.inkSoft : Theme.ink)
                    Text(info.summary)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(2)
                }
                Spacer()
                if paywalled {
                    Text("Unlock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.indigo)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.indigoWash))
                }
                Image(systemName: dimmed ? "lock" : "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(paywalled ? Theme.indigo : Theme.inkSoft)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            .opacity(dimmed ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(masteryLocked)
        // The badge is the only carrier of mastery state and is hidden from
        // VoiceOver, so without this every lesson reads identically whether it
        // is finished, available or locked.
        .accessibilityValue(rowState(state, paywalled: paywalled))
    }

    private func rowState(_ state: MasteryTracker.MasteryState, paywalled: Bool) -> String {
        if paywalled { return "locked, included in the full game" }
        switch state {
        case .learned: return "completed"
        case .locked: return "locked"
        default: return "not started"
        }
    }

    @ViewBuilder
    private func stateBadge(_ state: MasteryTracker.MasteryState,
                            isRules: Bool,
                            paywalled: Bool) -> some View {
        ZStack {
            Circle()
                .fill(state == .learned && !paywalled ? Theme.complete.opacity(0.18) : Theme.indigoWash)
                .frame(width: 38, height: 38)
            Image(systemName: paywalled ? "lock.fill"
                  : isRules ? "book"
                  : state == .learned ? "checkmark"
                  : state == .locked ? "lock" : "circle.dashed")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(state == .learned && !paywalled ? Theme.complete : Theme.indigo)
        }
        .accessibilityHidden(true)
    }
}

/// Per-technique drills with mastery progress.
struct PracticeMenuView: View {
    @Binding var path: [Route]
    @Environment(MasteryTracker.self) private var mastery
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(PaywallPresenter.self) private var paywall

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Technique.allCases) { technique in
                        row(technique)
                    }
                }
                .padding(20)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Practice")
        .navigationTitleDisplay(.large)
    }

    private func row(_ technique: Technique) -> some View {
        let record = mastery.record(for: technique)
        let masteryLocked = record.state == .locked
        // Drills are paid wholesale — mastery progress is itself a paid surface,
        // so a free player sees neither the bars nor the counts.
        let paywalled = !entitlements.isUnlocked
        let dimmed = masteryLocked || paywalled
        return Button {
            if paywalled {
                paywall.present(.practiceDrills)
            } else {
                path.append(.practice(technique))
            }
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(technique.displayName)
                        .font(.headline)
                        .foregroundStyle(dimmed ? Theme.inkSoft : Theme.ink)
                    Text(statusLine(record, paywalled: paywalled))
                        .font(.footnote)
                        .foregroundStyle(record.state == .learned && !paywalled
                                         ? Theme.complete : Theme.inkSoft)
                }
                Spacer()
                if paywalled {
                    Text("Unlock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.indigo)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.indigoWash))
                } else if record.state == .learned {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.complete)
                } else if !masteryLocked {
                    ProgressView(value: Double(min(record.unaidedUses, MasteryTracker.learnedThreshold)),
                                 total: Double(MasteryTracker.learnedThreshold))
                        .frame(width: 60)
                        .tint(Theme.indigo)
                }
                Image(systemName: dimmed ? "lock" : "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(paywalled ? Theme.indigo : Theme.inkSoft)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            .opacity(dimmed ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(masteryLocked)
    }

    private func statusLine(_ record: MasteryTracker.Record, paywalled: Bool) -> String {
        if paywalled { return "Included in the full game" }
        switch record.state {
        case .locked: return "Unlocks with the previous technique"
        case .learned: return "Learned · \(record.drillsCompleted) drills"
        default: return "\(record.unaidedUses)/\(MasteryTracker.learnedThreshold) unaided applications"
        }
    }
}
