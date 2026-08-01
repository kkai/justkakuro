import Foundation
import Observation

/// The one stateful game object: puzzle + player board + undo + timer.
@Observable @MainActor
final class KakuroGame {
    enum Phase: String, Codable {
        case playing, paused, won
    }

    let generated: GeneratedPuzzle
    var puzzle: KakuroPuzzle { generated.puzzle }

    private(set) var board = BoardState()
    private(set) var undoStack: [Move] = []
    private(set) var phase: Phase = .playing
    private(set) var elapsed: TimeInterval = 0
    var selected: GridPosition?
    var notesMode = false
    /// Digit currently highlighted from the pad (dims impossible cells).
    var highlightedDigit: Int?

    /// Board state immediately before the most recent move. Mastery tracking
    /// needs it to ask "would the solver have made this move?" — reconstructing
    /// it by deleting the entry doesn't work, because placing also clears the
    /// cell's notes and strips the digit from its run-mates.
    private(set) var boardBeforeLastMove: BoardState?

    private var lastTick: Date?

    /// The difficulty the player asked for, which is not always the one they
    /// got: `generate` returns the nearest band when its candidate budget runs
    /// out. Stats keys on this so a best time lands in the column the player
    /// actually chose, consistent with `PuzzleCache`, `Route` and
    /// `recordLastPlayed`. Optional so saves written before it existed still
    /// decode; those fall back to the delivered band.
    let requestedDifficulty: Difficulty?

    /// The difficulty a solve should be filed under.
    var difficultyForRecords: Difficulty { requestedDifficulty ?? generated.difficulty }

    init(puzzle: GeneratedPuzzle, requestedDifficulty: Difficulty? = nil) {
        self.generated = puzzle
        self.requestedDifficulty = requestedDifficulty
    }

    // MARK: - Input

    var canUndo: Bool { !undoStack.isEmpty }

    func tap(_ pos: GridPosition) {
        guard puzzle.cells[pos.row][pos.col].isWhite else {
            selected = nil
            return
        }
        selected = (selected == pos) ? nil : pos
    }

    func enter(_ digit: Int) {
        guard phase == .playing, let pos = selected else { return }
        if notesMode {
            toggleNote(digit, at: pos)
        } else {
            place(digit, at: pos)
        }
    }

    /// Where an arrow key would land, without moving anything.
    ///
    /// Black cells are stepped over rather than stopped at, so arrowing off the
    /// end of a run lands in the next one, the way it does in a crossword.
    /// Returns nil when there is nothing playable that way.
    ///
    /// Separate from `moveSelection` because the tutorial has to put the
    /// destination through `TutorialEngine.handleTap` rather than assigning it:
    /// a lesson that watches taps but not arrow keys could be walked out from
    /// under.
    func nextWhite(from origin: GridPosition?, _ direction: SelectionDirection) -> GridPosition? {
        guard let origin else { return puzzle.whitePositions.min() }
        let (dr, dc) = direction.delta
        var row = origin.row + dr
        var col = origin.col + dc
        while row >= 0, row < puzzle.rows, col >= 0, col < puzzle.cols {
            if puzzle.cells[row][col].isWhite {
                return GridPosition(row: row, col: col)
            }
            row += dr
            col += dc
        }
        return nil
    }

    /// Moves the selection one playable cell in `direction`. At the edge the
    /// selection stays put: silently deselecting loses the player's place
    /// mid-typing.
    func moveSelection(_ direction: SelectionDirection) {
        guard phase == .playing else { return }
        if let target = nextWhite(from: selected, direction) {
            selected = target
        }
    }

    /// Applies a keystroke. Every case routes to input that already exists, so
    /// the keyboard cannot do anything the on-screen pad cannot.
    func handle(_ command: PuzzleKeyCommand) {
        switch command {
        case .digit(let digit): enter(digit)
        case .erase: clearSelected()
        case .toggleNotes: notesMode.toggle()
        case .undo: undo()
        case .deselect: selected = nil
        case .move(let direction): moveSelection(direction)
        }
    }

    func place(_ digit: Int, at pos: GridPosition) {
        let old = board.entries[pos]
        guard old != digit else {
            clear(at: pos)
            return
        }
        var moves: [Move] = [.setEntry(pos, old: old, new: digit)]
        // Auto-clean: remove this digit from notes in both crossing runs
        // (single undoable batch with the entry).
        for run in puzzle.runs(containing: pos) {
            for cell in run.cells where cell != pos {
                let notes = board.notes(at: cell)
                if notes.contains(digit) {
                    moves.append(.setNotes(cell, old: notes, new: notes.subtracting([digit])))
                }
            }
        }
        let notes = board.notes(at: pos)
        if !notes.isEmpty {
            moves.append(.setNotes(pos, old: notes, new: []))
        }
        perform(moves.count == 1 ? moves[0] : .batch(moves))
        checkWin()
    }

    func clear(at pos: GridPosition) {
        guard let old = board.entries[pos] else { return }
        perform(.setEntry(pos, old: old, new: nil))
    }

    func clearSelected() {
        guard phase == .playing, let pos = selected else { return }
        if board.entries[pos] != nil {
            clear(at: pos)
        } else if !board.notes(at: pos).isEmpty {
            perform(.setNotes(pos, old: board.notes(at: pos), new: []))
        }
    }

    func toggleNote(_ digit: Int, at pos: GridPosition) {
        guard board.entries[pos] == nil else { return }
        let old = board.notes(at: pos)
        let new = old.contains(digit) ? old.subtracting([digit]) : old.union([digit])
        perform(.setNotes(pos, old: old, new: new))
    }

    func undo() {
        guard phase == .playing, let inverse = undoStack.popLast() else { return }
        inverse.apply(to: &board)
    }

    /// Cells that have already earned mastery credit in this game.
    ///
    /// Undo deliberately does not clear these. Placing a digit, undoing, and
    /// placing it again looks identical to a fresh deduction from the board
    /// state alone, so without this a player could farm a technique to
    /// "Learned" by tapping undo in a loop.
    private var creditedPositions: Set<GridPosition> = []

    /// Claims the one-off mastery credit for a cell. Returns false if this cell
    /// has already paid out.
    func claimMasteryCredit(at position: GridPosition) -> Bool {
        creditedPositions.insert(position).inserted
    }

    /// Applies a hint's placements/eliminations as one undoable batch.
    func apply(_ application: TechniqueApplication) {
        guard phase == .playing else { return }
        var moves: [Move] = []
        for elimination in application.eliminations {
            let old = board.notes(at: elimination.position)
            let removed = Set(DigitSet.digits(elimination.digits))
            // With no notes yet there is nothing to subtract from, so seed the
            // cell with what's currently possible — otherwise Apply would look
            // like it did nothing.
            let base = old.isEmpty ? basicCandidates(at: elimination.position) : old
            let new = base.subtracting(removed)
            if new != old {
                moves.append(.setNotes(elimination.position, old: old, new: new))
            }
        }
        for placement in application.placements {
            moves.append(.setEntry(placement.position,
                                   old: board.entries[placement.position],
                                   new: placement.digit))
        }
        guard !moves.isEmpty else { return }
        perform(moves.count == 1 ? moves[0] : .batch(moves))
        checkWin()
    }

    /// Fills notes with solver candidates at the basic level only
    /// (duplicate + magic block knowledge — never leaks harder deductions).
    func fillAutoNotes() {
        guard phase == .playing else { return }
        var state = LogicalSolver.State(puzzle: puzzle)
        state.entries = board.entries
        for pos in board.entries.keys {
            state.candidates[pos] = nil
        }
        // Apply only the first two curriculum techniques to fixpoint.
        while true {
            var probe = state
            if let step = LogicalSolver.detectDuplicateInRun(puzzle: puzzle, state: &probe)
                ?? LogicalSolver.detectMagicBlock(puzzle: puzzle, state: &probe) {
                LogicalSolver.applyStep(step, to: &state)
                if !step.placements.isEmpty { continue }
            } else {
                break
            }
        }
        var moves: [Move] = []
        for (pos, cands) in state.candidates {
            let old = board.notes(at: pos)
            let new = Set(DigitSet.digits(cands))
            if old != new {
                moves.append(.setNotes(pos, old: old, new: new))
            }
        }
        guard !moves.isEmpty else { return }
        perform(.batch(moves))
    }

    // MARK: - Queries for the UI

    /// Digits still placeable in a cell from run sums and placed digits alone.
    func basicCandidates(at pos: GridPosition) -> Set<Int> {
        guard board.entries[pos] == nil else { return [] }
        return Set((1...9).filter { !isImpossible(digit: $0, at: pos) })
    }

    func isImpossible(digit: Int, at pos: GridPosition) -> Bool {
        guard board.entries[pos] == nil else { return true }
        for run in puzzle.runs(containing: pos) {
            for cell in run.cells where cell != pos {
                if board.entries[cell] == digit { return true }
            }
            let union = SumCombinations.union(sum: run.sum, length: run.length)
            if !DigitSet.contains(union, digit) { return true }
        }
        return false
    }

    /// A run is complete and correct when all cells are filled with distinct
    /// digits reaching the sum.
    func isRunComplete(_ run: Run) -> Bool {
        var mask: UInt16 = 0
        var total = 0
        for cell in run.cells {
            guard let d = board.entries[cell] else { return false }
            if DigitSet.contains(mask, d) { return false }
            mask |= DigitSet.mask(d)
            total += d
        }
        return total == run.sum
    }

    /// Remaining combinations for a run given current entries (tap-a-clue).
    func remainingCombinations(for run: Run) -> [UInt16] {
        var used: UInt16 = 0
        for cell in run.cells {
            if let d = board.entries[cell] { used |= DigitSet.mask(d) }
        }
        return SumCombinations.combinations(sum: run.sum, length: run.length, usedDigits: used)
    }

    // MARK: - Timer

    func tick(now: Date = .now) {
        guard phase == .playing else { lastTick = nil; return }
        if let last = lastTick {
            elapsed += now.timeIntervalSince(last)
        }
        lastTick = now
    }

    func pause() {
        if phase == .playing { phase = .paused; lastTick = nil }
    }

    func resume() {
        if phase == .paused { phase = .playing }
    }

    // MARK: - Save / restore

    struct Snapshot: Codable {
        let generated: GeneratedPuzzle
        let board: BoardState
        let undoStack: [Move]
        let elapsed: TimeInterval
        /// Optional for backward compatibility with saves written before this
        /// field existed.
        var requestedDifficulty: Difficulty?
    }

    var snapshot: Snapshot {
        Snapshot(generated: generated, board: board, undoStack: undoStack,
                 elapsed: elapsed, requestedDifficulty: requestedDifficulty)
    }

    convenience init(snapshot: Snapshot) {
        self.init(puzzle: snapshot.generated,
                  requestedDifficulty: snapshot.requestedDifficulty)
        board = snapshot.board
        undoStack = snapshot.undoStack
        elapsed = snapshot.elapsed
    }

    // MARK: - Private

    private func perform(_ move: Move) {
        boardBeforeLastMove = board
        let inverse = move.apply(to: &board)
        undoStack.append(inverse)
    }

    private func checkWin() {
        if board.isSolved(for: puzzle) {
            phase = .won
            lastTick = nil
            selected = nil
        }
    }
}
