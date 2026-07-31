import Foundation

/// Hand-crafted lesson boards (machine-verified by TutorialFixtureTests) and
/// the lesson scripts themselves.
nonisolated enum TutorialPuzzles {

    // MARK: - Boards

    /// The 2x2 rules board: 3→ = {1,2}, 4↓ = {1,3} — every cell is forced.
    ///   .   4↓  7↓
    ///   3→  1   2
    ///   8→  3   5
    static var rulesBoard: KakuroPuzzle {
        KakuroBuilder.puzzle(fromSolutionGrid: [
            [nil, nil, nil],
            [nil, 1, 2],
            [nil, 3, 5],
        ])
    }

    /// Magic-block showcase: 17→ {8,9}, 16↓ {7,9}, 24→ {7,8,9}, 23↓ {6,8,9}.
    static var magicBoard: KakuroPuzzle {
        KakuroBuilder.puzzle(fromSolutionGrid: [
            [nil, nil, nil, nil],
            [nil, 9, 8, nil],
            [nil, 7, 9, 8],
            [nil, nil, 6, 9],
        ])
    }

    /// Cross-reference showcase: no run is magic, so intersections do all the
    /// work. Verified unique (many 2x2 sum sets are not — see TutorialFixtureTests).
    ///   .    8↓  10↓
    ///   12→  3   9
    ///   6→   5   1
    static var crossBoard: KakuroPuzzle {
        KakuroBuilder.puzzle(fromSolutionGrid: [
            [nil, nil, nil],
            [nil, 3, 9],
            [nil, 5, 1],
        ])
    }

    // MARK: - Lessons

    /// Cheap metadata for menus — building a full lesson may generate a board.
    struct LessonInfo: Identifiable {
        let technique: Technique?
        let title: String
        let summary: String
        var id: String { technique.map { "t\($0.rawValue)" } ?? "rules" }
    }

    static var lessonInfos: [LessonInfo] {
        [LessonInfo(technique: nil, title: "How Kakuro works",
                    summary: "Runs, clues, and the no-repeat rule")]
            + Technique.allCases.map {
                LessonInfo(technique: $0, title: $0.displayName,
                           summary: TechniqueContent.rule(for: $0))
            }
    }

    /// Builds the full lesson. May generate a drill board — call off-main.
    @MainActor
    static func lesson(for technique: Technique?) async -> TutorialLesson {
        switch technique {
        case nil: return rulesLesson
        case .magicBlock: return magicBlockLesson
        case .crossReference: return crossReferenceLesson
        case .some(let technique): return await generatedLesson(for: technique)
        }
    }

    @MainActor
    private static var rulesLesson: TutorialLesson {
        let a = GridPosition(row: 1, col: 1)
        let b = GridPosition(row: 1, col: 2)
        let c = GridPosition(row: 2, col: 1)
        let d = GridPosition(row: 2, col: 2)
        return TutorialLesson(
            id: "rules",
            technique: nil,
            title: "How Kakuro works",
            summary: "Runs, clues, and the no-repeat rule",
            puzzle: rulesBoard,
            steps: [
                .say("Kakuro is a crossword with sums instead of words. Each white cell takes a digit from 1 to 9."),
                .sayHighlighting("A row or column of white cells is a run. The clue in the split cell is the run's total — top-right for across, bottom-left for down.", [a, b, c, d]),
                .sayHighlighting("This across run must add to 3. Two different digits that sum to 3: only 1 and 2. A digit never repeats inside a run.", [a, b]),
                .sayHighlighting("Which order? The down clue decides. This column adds to 4 — so its two digits are 1 and 3. The shared cell must work for both.", [a, c]),
                .requireEntry("The shared cell appears in both {1,2} and {1,3} — it must be 1. Tap the pad to place it.", a, 1),
                .requireEntry("With 1 placed, the across run needs 2 more. Place the 2.", b, 2),
                .requireEntry("The down run needs 3 more. Place the 3.", c, 3),
                .requireEntry("Last cell: the bottom row must total 8, and 8 − 3 = 5.", d, 5),
                .celebrate("That's Kakuro: every run adds to its clue, no digit repeats in a run, and crossings decide the order. You just solved your first board."),
            ]
        )
    }

    @MainActor
    private static var magicBlockLesson: TutorialLesson {
        let topLeft = GridPosition(row: 1, col: 1)
        let topRight = GridPosition(row: 1, col: 2)
        return TutorialLesson(
            id: "magic",
            technique: .magicBlock,
            title: Technique.magicBlock.displayName,
            summary: "Sums with only one digit set",
            puzzle: magicBoard,
            steps: [
                .say(TechniqueContent.lesson(for: .magicBlock)),
                .sayHighlighting("17 across in two cells: the only pair is 8+9. That's a magic block — before knowing the order, you know the digits.", [topLeft, topRight]),
                .sayHighlighting("The crossing 16 down is also magic: {7,9}. The shared corner must be in both {8,9} and {7,9} — only 9 fits.", [topLeft]),
                .requireEntry("Place the 9 where the two magic blocks cross.", topLeft, 9),
                .requireEntry("The 17 run's other cell takes the remaining 8.", topRight, 8),
                .solveFreely("The rest of the board is magic blocks crossing magic blocks. Finish it — tap a clue any time to see a run's combinations."),
                .celebrate("Magic blocks first, always. Low sums (3, 4, 6, 7) and high sums (16, 17, 23, 24) are where every Kakuro cracks open."),
            ]
        )
    }

    @MainActor
    private static var crossReferenceLesson: TutorialLesson {
        let corner = GridPosition(row: 1, col: 1)
        return TutorialLesson(
            id: "cross",
            technique: .crossReference,
            title: Technique.crossReference.displayName,
            summary: "Two clues, one cell",
            puzzle: crossBoard,
            steps: [
                .say(TechniqueContent.lesson(for: .crossReference)),
                .sayHighlighting("No magic blocks here — 12 across can be 3+9, 4+8 or 5+7. But the down run's options overlap it in only a few digits.", [corner]),
                .requireNote("Work the corner: 12 across allows 3, 4, 5, 7, 8 and 9; 8 down allows 1, 2, 3, 5, 6 and 7. Note the overlap — 3, 5 and 7.", corner, [3, 5, 7]),
                .solveFreely("Keep crossing clues until digits are forced. Solve the board — notes are your friend."),
                .celebrate("Cross-referencing turns two vague clues into one sharp fact. With magic blocks, it carries you through most easy puzzles."),
            ]
        )
    }

    /// Techniques without a scripted board teach with a short lesson and a
    /// free-solve exam on a generated board known to require them.
    @MainActor
    private static func generatedLesson(for technique: Technique) async -> TutorialLesson {
        let generated = await Task.detached(priority: .userInitiated) {
            PracticeDrills.drillPuzzle(for: technique)
        }.value
        return TutorialLesson(
            id: "t\(technique.rawValue)",
            technique: technique,
            title: technique.displayName,
            summary: TechniqueContent.rule(for: technique),
            puzzle: generated.puzzle,
            steps: [
                .say(TechniqueContent.lesson(for: technique)),
                .say(TechniqueContent.rule(for: technique)),
                .solveFreely("Solve this board — it needs \(technique.displayName) at least once. The hint button teaches if you stall."),
                .celebrate("\(technique.displayName) added to your toolkit. Drill it in Practice to make it automatic."),
            ]
        )
    }
}
