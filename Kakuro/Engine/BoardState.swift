import Foundation

/// Player-visible board state: entries and pencil notes. Pure value type so it
/// snapshots cleanly for undo and persistence.
nonisolated struct BoardState: Codable, Sendable, Equatable {
    var entries: [GridPosition: Int] = [:]
    var notes: [GridPosition: Set<Int>] = [:]

    func entry(at pos: GridPosition) -> Int? {
        entries[pos]
    }

    func notes(at pos: GridPosition) -> Set<Int> {
        notes[pos] ?? []
    }

    func isComplete(for puzzle: KakuroPuzzle) -> Bool {
        puzzle.whitePositions.allSatisfy { entries[$0] != nil }
    }

    func isSolved(for puzzle: KakuroPuzzle) -> Bool {
        puzzle.whitePositions.allSatisfy { entries[$0] == puzzle.solution(at: $0) }
    }
}

nonisolated enum Move: Codable, Sendable, Equatable {
    case setEntry(GridPosition, old: Int?, new: Int?)
    case setNotes(GridPosition, old: Set<Int>, new: Set<Int>)
    case batch([Move])

    /// Applies the move to a board, returning the inverse move for undo.
    @discardableResult
    func apply(to board: inout BoardState) -> Move {
        switch self {
        case .setEntry(let pos, let old, let new):
            board.entries[pos] = new
            return .setEntry(pos, old: new, new: old)
        case .setNotes(let pos, let old, let new):
            board.notes[pos] = new.isEmpty ? nil : new
            return .setNotes(pos, old: new, new: old)
        case .batch(let moves):
            let inverses = moves.map { $0.apply(to: &board) }
            return .batch(inverses.reversed())
        }
    }

    var inverse: Move {
        switch self {
        case .setEntry(let pos, let old, let new):
            .setEntry(pos, old: new, new: old)
        case .setNotes(let pos, let old, let new):
            .setNotes(pos, old: new, new: old)
        case .batch(let moves):
            .batch(moves.reversed().map(\.inverse))
        }
    }
}
