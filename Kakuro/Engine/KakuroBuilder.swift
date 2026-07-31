import Foundation

/// Builds a complete `KakuroPuzzle` (runs, clue cells) from a solution grid.
/// `nil` marks a non-white cell; digits mark white cells. Shared by the
/// generator (after digit fill), test fixtures, and tutorial puzzles.
nonisolated enum KakuroBuilder {

    /// Derives runs and clue cells from a solution grid. Non-white cells that
    /// head a run become clue cells; all others become blocks.
    static func puzzle(fromSolutionGrid grid: [[Int?]]) -> KakuroPuzzle {
        let rows = grid.count
        let cols = grid.first?.count ?? 0

        var runs: [Run] = []
        var clueSums: [GridPosition: (across: Int?, down: Int?)] = [:]

        func addRun(cells: [GridPosition], orientation: RunOrientation, clue: GridPosition) {
            guard cells.count >= 2 else { return }
            let sum = cells.reduce(0) { $0 + (grid[$1.row][$1.col] ?? 0) }
            runs.append(Run(id: runs.count, orientation: orientation, sum: sum,
                            cells: cells, clueCell: clue))
            var entry = clueSums[clue] ?? (nil, nil)
            switch orientation {
            case .across: entry.across = sum
            case .down: entry.down = sum
            }
            clueSums[clue] = entry
        }

        // Across runs: maximal horizontal strips of white cells.
        for r in 0..<rows {
            var c = 0
            while c < cols {
                if grid[r][c] != nil {
                    let start = c
                    var cells: [GridPosition] = []
                    while c < cols, grid[r][c] != nil {
                        cells.append(GridPosition(row: r, col: c))
                        c += 1
                    }
                    addRun(cells: cells, orientation: .across,
                           clue: GridPosition(row: r, col: start - 1))
                } else {
                    c += 1
                }
            }
        }

        // Down runs: maximal vertical strips.
        for c in 0..<cols {
            var r = 0
            while r < rows {
                if grid[r][c] != nil {
                    let start = r
                    var cells: [GridPosition] = []
                    while r < rows, grid[r][c] != nil {
                        cells.append(GridPosition(row: r, col: c))
                        r += 1
                    }
                    addRun(cells: cells, orientation: .down,
                           clue: GridPosition(row: start - 1, col: c))
                } else {
                    r += 1
                }
            }
        }

        var cells: [[Cell]] = []
        for r in 0..<rows {
            var row: [Cell] = []
            for c in 0..<cols {
                let pos = GridPosition(row: r, col: c)
                if let digit = grid[r][c] {
                    row.append(.white(solution: digit))
                } else if let sums = clueSums[pos] {
                    row.append(.clue(across: sums.across, down: sums.down))
                } else {
                    row.append(.block)
                }
            }
            cells.append(row)
        }

        return KakuroPuzzle(rows: rows, cols: cols, cells: cells, runs: runs)
    }

    /// Validates that a solution grid is a legal Kakuro layout:
    /// every white cell is part of runs of length 2-9, and no run repeats a digit.
    static func isValidLayout(_ grid: [[Int?]]) -> Bool {
        let puzzle = puzzle(fromSolutionGrid: grid)
        // Every white cell must belong to at least one run (no orphan cells),
        // and both of its runs (where present) must have legal length.
        for pos in puzzle.whitePositions {
            let runs = puzzle.runs(containing: pos)
            if runs.isEmpty { return false }
            // A white cell with a same-orientation neighbor is covered by that run;
            // a stranded single white cell in one direction is allowed only if the
            // strip has length 1 (no run recorded) — Kakuro requires length >= 2 both ways
            // wherever a strip exists, so check strips directly below.
        }
        // Check horizontal and vertical strip lengths: every maximal strip must be 2-9.
        let rows = grid.count
        let cols = grid.first?.count ?? 0
        for r in 0..<rows {
            var c = 0
            while c < cols {
                if grid[r][c] != nil {
                    var len = 0
                    while c < cols, grid[r][c] != nil { len += 1; c += 1 }
                    if len < 2 || len > 9 { return false }
                } else { c += 1 }
            }
        }
        for c in 0..<cols {
            var r = 0
            while r < rows {
                if grid[r][c] != nil {
                    var len = 0
                    while r < rows, grid[r][c] != nil { len += 1; r += 1 }
                    if len < 2 || len > 9 { return false }
                } else { r += 1 }
            }
        }
        // No duplicate digits within any run.
        for run in puzzle.runs {
            var seen: UInt16 = 0
            for pos in run.cells {
                guard let d = grid[pos.row][pos.col] else { return false }
                if DigitSet.contains(seen, d) { return false }
                seen |= DigitSet.mask(d)
            }
        }
        return true
    }
}
