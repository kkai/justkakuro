import SwiftUI

/// A tapped clue cell and the runs it heads. A clue can start both an across
/// and a down run, so the sheet shows either or both.
struct ClueSelection: Identifiable {
    let position: GridPosition
    let runs: [Run]
    var id: GridPosition { position }
}

/// Tap-a-clue: the remaining digit combinations for each run this clue heads,
/// given current entries. Busywork reduction, not a spoiler — it lists digit
/// sets, never which cell takes which digit.
struct CombinationSheet: View {
    let selection: ClueSelection
    let combinations: (Run) -> [UInt16]

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .top) {
                Spacer(minLength: 0)
                SheetCloseButton()
            }
            ForEach(selection.runs) { run in
                CombinationPopover(run: run, combinations: combinations(run))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .mediumSheet()
        .presentationBackground(Theme.paper)
    }
}

struct CombinationPopover: View {
    let run: Run
    let combinations: [UInt16]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: run.orientation == .across ? "arrow.right" : "arrow.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.inkSoft)
                Text("\(run.sum) in \(run.length)")
                    .font(Theme.heading)
                    .foregroundStyle(Theme.ink)
                if combinations.count == 1 {
                    Text("magic block")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.indigo)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.indigoWash))
                }
            }
            if combinations.isEmpty {
                Text("No combination fits the current entries, so something is off in this run.")
                    .font(.footnote)
                    .foregroundStyle(Theme.error)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(combinations, id: \.self) { combo in
                        Text(DigitSet.digits(combo).map(String.init).joined(separator: " + "))
                            .font(Theme.digitFont(size: 17))
                            .foregroundStyle(Theme.ink)
                    }
                }
            }
        }
        .padding(16)
        .presentationCompactAdaptation(.popover)
    }
}
