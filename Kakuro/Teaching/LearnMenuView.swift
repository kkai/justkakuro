import SwiftUI

/// The curriculum as a progress path: rules first, then one lesson per
/// technique, unlocking in order.
struct LearnMenuView: View {
    @Binding var path: [Route]
    @Environment(MasteryTracker.self) private var mastery

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
        .navigationBarTitleDisplayMode(.large)
    }

    private func lessonRow(_ info: TutorialPuzzles.LessonInfo) -> some View {
        let state = info.technique.map { mastery.state(of: $0) } ?? .learned
        let locked = state == .locked
        return Button {
            path.append(.tutorial(info.technique))
        } label: {
            HStack(spacing: 14) {
                stateBadge(state, isRules: info.technique == nil)
                VStack(alignment: .leading, spacing: 3) {
                    Text(info.title)
                        .font(.headline)
                        .foregroundStyle(locked ? Theme.inkSoft : Theme.ink)
                    Text(info.summary)
                        .font(.footnote)
                        .foregroundStyle(Theme.inkSoft)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: locked ? "lock" : "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            .opacity(locked ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(locked)
    }

    @ViewBuilder
    private func stateBadge(_ state: MasteryTracker.MasteryState, isRules: Bool) -> some View {
        ZStack {
            Circle()
                .fill(state == .learned ? Theme.complete.opacity(0.18) : Theme.indigoWash)
                .frame(width: 38, height: 38)
            Image(systemName: isRules ? "book"
                  : state == .learned ? "checkmark"
                  : state == .locked ? "lock" : "circle.dashed")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(state == .learned ? Theme.complete : Theme.indigo)
        }
        .accessibilityHidden(true)
    }
}

/// Per-technique drills with mastery progress.
struct PracticeMenuView: View {
    @Binding var path: [Route]
    @Environment(MasteryTracker.self) private var mastery

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
        .navigationBarTitleDisplayMode(.large)
    }

    private func row(_ technique: Technique) -> some View {
        let record = mastery.record(for: technique)
        let locked = record.state == .locked
        return Button {
            path.append(.practice(technique))
        } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(technique.displayName)
                        .font(.headline)
                        .foregroundStyle(locked ? Theme.inkSoft : Theme.ink)
                    Text(statusLine(record))
                        .font(.footnote)
                        .foregroundStyle(record.state == .learned ? Theme.complete : Theme.inkSoft)
                }
                Spacer()
                if record.state == .learned {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Theme.complete)
                } else if !locked {
                    ProgressView(value: Double(min(record.unaidedUses, MasteryTracker.learnedThreshold)),
                                 total: Double(MasteryTracker.learnedThreshold))
                        .frame(width: 60)
                        .tint(Theme.indigo)
                }
                Image(systemName: locked ? "lock" : "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.inkSoft)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.surface))
            .opacity(locked ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(locked)
    }

    private func statusLine(_ record: MasteryTracker.Record) -> String {
        switch record.state {
        case .locked: "Unlocks with the previous technique"
        case .learned: "Learned · \(record.drillsCompleted) drills"
        default: "\(record.unaidedUses)/\(MasteryTracker.learnedThreshold) unaided applications"
        }
    }
}
