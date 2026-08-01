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
    /// tvOS: Select pressed on an already-focused white cell. The screen above
    /// decides what that opens, which keeps the tutorial's input filter intact.
    var onActivate: ((GridPosition) -> Void)? = nil

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// tvOS only. The remote has no pointer, so the focus engine is the cursor:
    /// cells must be focusable or the board cannot be reached at all. Focus and
    /// selection are deliberately the same thing here. Keeping them apart would
    /// mean the player moves a focus ring, clicks to select, and only then
    /// enters a digit, which is one whole state more than a remote should ask
    /// for. Black cells are left unfocusable so the engine steps over them.
    @FocusState private var focusedCell: GridPosition?

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
            let cellSize = min(fitted, Metrics.cellCap)
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
            #if os(tvOS)
            // tvOS renders dark, where `block` and `paper` sit close enough that
            // the board loses its silhouette and reads as a hole in the screen.
            // An outline gives it an edge to sit inside.
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .inset(by: -2)
                    .stroke(Theme.hairline, lineWidth: 3)
                    .frame(width: boardWidth, height: boardHeight)
            }
            #endif
        }
        .aspectRatio(CGFloat(game.puzzle.cols) / CGFloat(game.puzzle.rows), contentMode: .fit)
        .onAppear {
            appeared = true
            #if os(tvOS)
            // Land on a real square rather than wherever the focus engine
            // happens to start. A board that opens with nothing focused makes
            // the first press of the remote feel like it did nothing.
            focusedCell = game.selected ?? game.puzzle.whitePositions.min()
            #endif
        }
        #if os(tvOS)
        // Moving focus IS moving the selection. Guarded on whiteness because the
        // clue cells are focusable too, and landing on one should not clear a
        // selection the player is working with.
        .onChange(of: focusedCell) { _, pos in
            guard let pos, game.puzzle.cells[pos.row][pos.col].isWhite else { return }
            game.selected = pos
        }
        #endif
    }

    @ViewBuilder
    private func cell(at pos: GridPosition, size: CGFloat) -> some View {
        switch game.puzzle.cells[pos.row][pos.col] {
        case .block:
            Rectangle()
                .fill(Theme.block)
                .frame(width: size, height: size)
        case .clue(let across, let down):
            #if os(tvOS)
            // Not a focus stop. Making every clue focusable doubled the number
            // of presses needed to cross the board, and the remote has to travel
            // far enough already. The combinations a clue would have shown are
            // still reachable through the hint button.
            ClueCellView(across: across, down: down, size: size)
            #else
            reachable(pos) {
                ClueCellView(across: across, down: down, size: size)
            } activate: {
                (onTap ?? { game.tap($0) })(pos)
            }
            #endif
        case .white:
            reachable(pos) {
                WhiteCellView(
                    game: game,
                    position: pos,
                    size: size,
                    isHighlighted: highlighted.contains(pos),
                    sweepIndex: sweep[pos]
                )
            } activate: {
                #if os(tvOS)
                // Focus already selected this cell, so Select means "enter a
                // digit here", not "select". Routing it through `game.tap`
                // would toggle the selection straight back off.
                onActivate?(pos)
                #else
                (onTap ?? { game.tap($0) })(pos)
                #endif
            }
        }
    }

    /// Wraps a cell so it can be reached by whatever input the platform has.
    ///
    /// A tap gesture is enough where there is a finger or a pointer. On tvOS
    /// there is neither, so the cell has to be a real focusable control or the
    /// focus engine will not visit it and the board is inert.
    @ViewBuilder
    private func reachable<Content: View>(_ pos: GridPosition,
                                          @ViewBuilder content: () -> Content,
                                          activate: @escaping () -> Void) -> some View {
        #if os(tvOS)
        // A focusable view rather than a Button. A Button drags the system focus
        // treatment along with it: even with `.plain` and `.focusEffectDisabled`
        // a white halo kept bleeding out past the grid and tearing a hole in the
        // board. A plain focusable view has no chrome to suppress, and on tvOS
        // `onTapGesture` is what the Select button fires.
        content()
            .contentShape(Rectangle())
            .focusable(true)
            .focused($focusedCell, equals: pos)
            .onTapGesture(perform: activate)
        #else
        content()
            .contentShape(Rectangle())
            .onTapGesture(perform: activate)
        #endif
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
                // On tvOS this ring is the cursor, seen from across a room, so
                // it is drawn far heavier than the 2pt hairline a phone needs.
                RoundedRectangle(cornerRadius: 2)
                    .stroke(Theme.indigo, lineWidth: Metrics.selectionRing)
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
