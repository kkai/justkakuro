import SwiftUI

/// The Kakuro grid. GeometryReader computes a cell size that fits the
/// available space; cells render by kind (block / clue / white).
struct BoardView: View {
    let game: KakuroGame
    /// Cells to emphasize (hints, tutorial highlights).
    var highlighted: Set<GridPosition> = []
    /// Cells recently completed, for the run sweep (position → stagger index).
    var sweep: [GridPosition: Int] = [:]
    var onTap: ((GridPosition) -> Void)? = nil

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { proxy in
            let dimension = CGFloat(max(game.puzzle.rows, game.puzzle.cols))
            let gap: CGFloat = 1
            // Capped, because a Mac window has no natural width the way a phone
            // does, and a maximised one would otherwise give 9 cells the full
            // height of a 27-inch display.
            //
            // The cap is deliberately loose. At 64 it bound at the default
            // window size, so the board stopped growing while there was still
            // room and left a band of dead space under it. At 88 the ordinary
            // case is limited by the space available, the way it is on a phone,
            // and the cap only steps in once the window is genuinely large.
            let fitted = ((min(proxy.size.width, proxy.size.height)
                           - gap * (dimension - 1)) / dimension).rounded(.down)
            let cellSize = min(fitted, 88)
            let boardWidth = cellSize * CGFloat(game.puzzle.cols) + gap * (CGFloat(game.puzzle.cols) - 1)
            let boardHeight = cellSize * CGFloat(game.puzzle.rows) + gap * (CGFloat(game.puzzle.rows) - 1)

            VStack(spacing: gap) {
                ForEach(0..<game.puzzle.rows, id: \.self) { row in
                    HStack(spacing: gap) {
                        ForEach(0..<game.puzzle.cols, id: \.self) { col in
                            let pos = GridPosition(row: row, col: col)
                            cell(at: pos, size: cellSize)
                                .opacity(appeared || reduceMotion ? 1 : 0)
                                .offset(y: appeared || reduceMotion ? 0 : 10)
                                .animation(
                                    reduceMotion ? nil : Motion.boardEntrance.delay(
                                        Double(row + col) * Motion.boardEntranceStagger),
                                    value: appeared)
                        }
                    }
                }
            }
            .frame(width: boardWidth, height: boardHeight)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .aspectRatio(CGFloat(game.puzzle.cols) / CGFloat(game.puzzle.rows), contentMode: .fit)
        .onAppear { appeared = true }
    }

    @ViewBuilder
    private func cell(at pos: GridPosition, size: CGFloat) -> some View {
        switch game.puzzle.cells[pos.row][pos.col] {
        case .block:
            Rectangle()
                .fill(Theme.block)
                .frame(width: size, height: size)
        case .clue(let across, let down):
            ClueCellView(across: across, down: down, size: size)
                .contentShape(Rectangle())
                .onTapGesture {
                    (onTap ?? { game.tap($0) })(pos)
                }
        case .white:
            WhiteCellView(
                game: game,
                position: pos,
                size: size,
                isHighlighted: highlighted.contains(pos),
                sweepIndex: sweep[pos]
            )
            .onTapGesture {
                (onTap ?? { game.tap($0) })(pos)
            }
        }
    }
}

/// Clue cell: the app's signature element. A fine diagonal splits the cell;
/// the across sum sits top-right, the down sum bottom-left.
struct ClueCellView: View {
    let across: Int?
    let down: Int?
    let size: CGFloat

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.block)
            DiagonalLine()
                .stroke(Theme.clueText.opacity(0.45), lineWidth: 0.8)
                .padding(size * 0.08)
            if let across {
                Text("\(across)")
                    .font(Theme.clueFont(size: size * 0.30))
                    .foregroundStyle(Theme.clueText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, size * 0.08)
                    .padding(.trailing, size * 0.10)
            }
            if let down {
                Text("\(down)")
                    .font(Theme.clueFont(size: size * 0.30))
                    .foregroundStyle(Theme.clueText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(.bottom, size * 0.08)
                    .padding(.leading, size * 0.10)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel(clueAccessibilityLabel)
    }

    private var clueAccessibilityLabel: String {
        var parts: [String] = []
        if let across { parts.append("across sum \(across)") }
        if let down { parts.append("down sum \(down)") }
        return parts.isEmpty ? "block" : parts.joined(separator: ", ")
    }
}

struct DiagonalLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

/// White cell: entry digit, notes, selection and relation washes.
struct WhiteCellView: View {
    let game: KakuroGame
    let position: GridPosition
    let size: CGFloat
    let isHighlighted: Bool
    let sweepIndex: Int?

    @State private var entryScale: CGFloat = 1

    private var entry: Int? { game.board.entry(at: position) }
    private var isSelected: Bool { game.selected == position }
    private var isRelated: Bool {
        guard let selected = game.selected, selected != position else { return false }
        return game.puzzle.runs(containing: selected)
            .contains { $0.cells.contains(position) }
    }
    private var isDimmed: Bool {
        guard let digit = game.highlightedDigit else { return false }
        return game.isImpossible(digit: digit, at: position)
    }

    var body: some View {
        ZStack {
            Rectangle().fill(background)
            if let entry {
                Text("\(entry)")
                    .font(Theme.digitFont(size: size * 0.52))
                    .foregroundStyle(Theme.ink)
                    .scaleEffect(entryScale)
            } else {
                NotesGridView(notes: game.board.notes(at: position), size: size)
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Theme.indigo, lineWidth: 2)
            }
        }
        .opacity(isDimmed ? 0.35 : 1)
        .animation(Motion.selection, value: isSelected)
        .animation(Motion.noteFlip, value: isDimmed)
        // Stagger the completion wash along the run so it reads as a sweep.
        .animation(Motion.runComplete.delay(Double(sweepIndex ?? 0) * Motion.runCompleteStagger),
                   value: sweepIndex)
        .onChange(of: entry) { old, new in
            guard new != nil, old != new else { return }
            entryScale = 1.12
            withAnimation(Motion.digitEntry) { entryScale = 1 }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityDescription)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var background: Color {
        if sweepIndex != nil { return Theme.complete.opacity(0.25) }
        if isHighlighted { return Theme.indigoWash }
        if isSelected { return Theme.indigoWash }
        if isRelated { return Theme.indigoWash.opacity(0.5) }
        return Theme.surface
    }

    private var accessibilityDescription: String {
        if let entry { return "row \(position.row), column \(position.col), \(entry)" }
        let notes = game.board.notes(at: position).sorted()
        if notes.isEmpty { return "row \(position.row), column \(position.col), empty" }
        return "row \(position.row), column \(position.col), notes \(notes.map(String.init).joined(separator: " "))"
    }
}

/// 3x3 pencil-note layout, digits in fixed positions.
struct NotesGridView: View {
    let notes: Set<Int>
    let size: CGFloat

    var body: some View {
        if !notes.isEmpty {
            VStack(spacing: 0) {
                ForEach(0..<3, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(1...3, id: \.self) { col in
                            let digit = row * 3 + col
                            Text(notes.contains(digit) ? "\(digit)" : " ")
                                .font(Theme.noteFont(size: size * 0.2))
                                .foregroundStyle(Theme.inkSoft)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                }
            }
            .padding(size * 0.06)
        }
    }
}
