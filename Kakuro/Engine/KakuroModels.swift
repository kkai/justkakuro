import Foundation

nonisolated struct GridPosition: Hashable, Codable, Sendable, Comparable {
    let row: Int
    let col: Int

    static func < (lhs: GridPosition, rhs: GridPosition) -> Bool {
        lhs.row != rhs.row ? lhs.row < rhs.row : lhs.col < rhs.col
    }
}

nonisolated enum Cell: Equatable, Codable, Sendable {
    case block
    case clue(across: Int?, down: Int?)
    case white(solution: Int)

    var isWhite: Bool {
        if case .white = self { return true }
        return false
    }
}

nonisolated enum RunOrientation: String, Codable, Sendable {
    case across, down
}

nonisolated struct Run: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let orientation: RunOrientation
    let sum: Int
    let cells: [GridPosition]
    let clueCell: GridPosition

    var length: Int { cells.count }
}

nonisolated struct KakuroPuzzle: Codable, Sendable, Equatable {
    let rows: Int
    let cols: Int
    let cells: [[Cell]]
    let runs: [Run]

    // Rebuilt on init/decode rather than encoded: maps each white cell to its (across, down) run ids.
    private(set) var runIndex: [GridPosition: RunPair] = [:]

    nonisolated struct RunPair: Codable, Sendable, Equatable {
        var across: Int?
        var down: Int?
    }

    private enum CodingKeys: String, CodingKey {
        case rows, cols, cells, runs
    }

    init(rows: Int, cols: Int, cells: [[Cell]], runs: [Run]) {
        self.rows = rows
        self.cols = cols
        self.cells = cells
        self.runs = runs
        buildRunIndex()
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        rows = try container.decode(Int.self, forKey: .rows)
        cols = try container.decode(Int.self, forKey: .cols)
        cells = try container.decode([[Cell]].self, forKey: .cells)
        runs = try container.decode([Run].self, forKey: .runs)
        buildRunIndex()
    }

    private mutating func buildRunIndex() {
        for run in runs {
            for pos in run.cells {
                var pair = runIndex[pos] ?? RunPair()
                switch run.orientation {
                case .across: pair.across = run.id
                case .down: pair.down = run.id
                }
                runIndex[pos] = pair
            }
        }
    }

    var whitePositions: [GridPosition] {
        var positions: [GridPosition] = []
        for r in 0..<rows {
            for c in 0..<cols where cells[r][c].isWhite {
                positions.append(GridPosition(row: r, col: c))
            }
        }
        return positions
    }

    func solution(at pos: GridPosition) -> Int? {
        guard case .white(let value) = cells[pos.row][pos.col] else { return nil }
        return value
    }

    func run(withID id: Int) -> Run {
        runs[id]
    }

    func runs(containing pos: GridPosition) -> [Run] {
        guard let pair = runIndex[pos] else { return [] }
        return [pair.across, pair.down].compactMap { $0 }.map { runs[$0] }
    }
}

nonisolated struct GeneratedPuzzle: Codable, Sendable, Equatable {
    let puzzle: KakuroPuzzle
    let difficulty: Difficulty
    let techniqueProfile: [Technique: Int]
}

nonisolated enum BoardSize: String, CaseIterable, Codable, Sendable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    /// Total grid dimension including the clue border row/column.
    var dimension: Int {
        switch self {
        case .small: 7
        case .medium: 9
        case .large: 11
        }
    }

    var displayName: String {
        switch self {
        case .small: "Small"
        case .medium: "Medium"
        case .large: "Large"
        }
    }
}
