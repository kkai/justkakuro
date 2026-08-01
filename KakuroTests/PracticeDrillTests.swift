import Foundation
import Testing
@testable import Kakuro

/// The old drill search silently shipped three boards that never exercised the
/// technique they advertised, because the only assertion covered two of eight.
@Suite struct PracticeDrillTests {

    /// Every drill, hand-authored or searched, must be a legal shippable board.
    @Test(arguments: Technique.allCases)
    func everyDrillIsUniqueAndLogicallySolvable(_ technique: Technique) {
        for variant in UInt64(0)..<3 {
            let drill = PracticeDrills.drillPuzzle(for: technique, variant: variant)
            let counted = BacktrackingSolver.countSolutions(drill.puzzle, limit: 2,
                                                            nodeLimit: 200_000)
            #expect(!counted.aborted, "\(technique) v\(variant): uniqueness check aborted")
            #expect(counted.count == 1, "\(technique) v\(variant) is not unique")
            #expect(LogicalSolver.solve(drill.puzzle).solved,
                    "\(technique) v\(variant) is not logically solvable")
        }
    }

    /// A searched drill must actually use its technique. The three that cannot
    /// be searched are excluded here and covered by the test below instead.
    @Test func searchedDrillsExerciseTheirTechnique() {
        for technique in Technique.allCases where !PracticeDrills.handAuthored.contains(technique) {
            for variant in UInt64(0)..<3 {
                let drill = PracticeDrills.drillPuzzle(for: technique, variant: variant)
                let uses = drill.techniqueProfile[technique] ?? 0
                #expect(uses >= PracticeDrills.minimumUses(of: technique),
                        "\(technique) v\(variant) drill uses it \(uses) times")
            }
        }
    }

    /// Pins why the other three are hand-authored: they appear in no solve trace
    /// the generator can produce, so a search for them cannot succeed. If this
    /// ever starts failing, the solver's detector precedence changed and these
    /// boards could go back to being searched.
    @Test func handAuthoredTechniquesAreUnsearchable() {
        for technique in PracticeDrills.handAuthored {
            #expect(!PracticeDrills.bakedGrids(for: technique).isEmpty,
                    "\(technique) is listed as hand-authored but has no board")
            var seen = 0
            for seed in UInt64(0)..<8 {
                let g = KakuroGenerator.generate(
                    .init(size: .small, difficulty: .medium, seed: 0xD00D &+ seed &* 331))
                seen += g.techniqueProfile[technique] ?? 0
            }
            #expect(seen == 0, "\(technique) now appears in generated traces — re-check the drill")
        }
    }

    /// Drills are the loading screen the player waits on, so keep them quick.
    /// The searched path used to run up to 25 full generations.
    @Test func everyDrillBuildsQuickly() {
        for technique in Technique.allCases {
            let start = ContinuousClock.now
            _ = PracticeDrills.drillPuzzle(for: technique)
            let elapsed = start.duration(to: .now)
            #expect(elapsed < .seconds(2),
                    "\(technique) drill took \(elapsed)")
        }
    }

    /// Cancellation must actually stop the search rather than being ignored.
    @Test func cancelledDrillStillReturnsAShippableBoard() {
        for technique in Technique.allCases {
            let drill = PracticeDrills.drillPuzzle(
                for: technique, control: .init(isCancelled: { true }))
            #expect(BacktrackingSolver.countSolutions(drill.puzzle, limit: 2).count == 1,
                    "\(technique): cancelled drill is not unique")
        }
    }
}
