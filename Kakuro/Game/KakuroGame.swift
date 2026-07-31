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

    init(puzzle: GeneratedPuzzle) {
        self.generated = puzzle
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
    }

    var snapshot: Snapshot {
        Snapshot(generated: generated, board: board, undoStack: undoStack, elapsed: elapsed)
    }

    convenience init(snapshot: Snapshot) {
        self.init(puzzle: snapshot.generated)
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
