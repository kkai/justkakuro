import Foundation
@testable import Kakuro

/// Hand-crafted puzzles with known properties, built via KakuroBuilder.
enum Fixtures {

    /// 3x3, 2x2 white block. Hand-verified unique solution:
    ///   .   4↓  7↓
    ///   3→  1   2
    ///   8→  3   5
    /// (2,1/1,2 across fails because col 1 would repeat a digit.)
    static var tiny2x2Unique: KakuroPuzzle {
        KakuroBuilder.puzzle(fromSolutionGrid: [
            [nil, nil, nil],
            [nil, 1, 2],
            [nil, 3, 5],
        ])
    }

    /// Same shape but all sums are 6 — at least two valid fills
    /// (1,5/5,1 and 2,4/4,2), so NOT unique. Built from one of them.
    static var tiny2x2Ambiguous: KakuroPuzzle {
        KakuroBuilder.puzzle(fromSolutionGrid: [
            [nil, nil, nil],
            [nil, 1, 5],
            [nil, 5, 1],
        ])
    }

    /// 4x4 L-shape, hand-verified unique. Magic blocks (17→ = {8,9},
    /// 16↓ = {7,9}, 24→ = {7,8,9}, 23↓ = {6,8,9}) force every cell:
    ///   .   16↓ 23↓ .
    ///   17→ 9   8   17↓
    ///   24→ 7   9   8
    ///   .   15→ 6   9
    static var small4x4: KakuroPuzzle {
        KakuroBuilder.puzzle(fromSolutionGrid: [
            [nil, nil, nil, nil],
            [nil, 9, 8, nil],
            [nil, 7, 9, 8],
            [nil, nil, 6, 9],
        ])
    }

    /// 5x5 with long runs. Hand-verified NOT unique (a2=7/a2=9 symmetric swap
    /// both satisfy all sums), so used to exercise multi-solution search and
    /// "found solutions include the seed grid".
    static var medium5x5Ambiguous: KakuroPuzzle {
        KakuroBuilder.puzzle(fromSolutionGrid: [
            [nil, nil, nil, nil, nil],
            [nil, nil, 9, 7, 8],
            [nil, 8, 6, 9, 7],
            [nil, 9, 7, 8, nil],
            [nil, nil, 8, 6, nil],
        ])
    }

    /// The seed solution of a fixture as an assignment map, for comparing
    /// against solver output.
    static func assignment(of puzzle: KakuroPuzzle) -> [GridPosition: Int] {
        var result: [GridPosition: Int] = [:]
        for pos in puzzle.whitePositions {
            result[pos] = puzzle.solution(at: pos)
        }
        return result
    }
}
