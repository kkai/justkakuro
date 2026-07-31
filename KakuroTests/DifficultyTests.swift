import Foundation
import Testing
@testable import Kakuro

@Suite struct DifficultyTests {

    @Test func weightsAreMonotoneInCurriculumTiers() {
        // Later, harder techniques must never be cheaper than the basics.
        #expect(DifficultyRater.weight(for: .combinationReduction)
                > DifficultyRater.weight(for: .magicBlock))
        #expect(DifficultyRater.weight(for: .surplusDeficit)
                > DifficultyRater.weight(for: .combinationReduction))
        #expect(DifficultyRater.weight(for: .hiddenSingle)
                > DifficultyRater.weight(for: .nakedSingle))
    }

    @Test func scoreAddsUp() {
        let profile: [Technique: Int] = [.magicBlock: 3, .nakedSingle: 2]
        let expected = 3 * DifficultyRater.weight(for: .magicBlock)
            + 2 * DifficultyRater.weight(for: .nakedSingle)
        #expect(DifficultyRater.score(profile: profile, solved: true) == expected)
        // Unsolved puzzles (guessing required) are penalized into the top band.
        #expect(DifficultyRater.score(profile: profile, solved: false) > expected + 400)
    }

    @Test func bandsPartitionScores() {
        for size in BoardSize.allCases {
            #expect(DifficultyRater.band(forScore: 0, size: size) == .easy)
            #expect(DifficultyRater.band(forScore: 10_000, size: size) == .hard)
            let t = DifficultyRater.thresholds[size]!
            #expect(DifficultyRater.band(forScore: t.easyMax, size: size) == .easy)
            #expect(DifficultyRater.band(forScore: t.easyMax + 1, size: size) == .medium)
            #expect(DifficultyRater.band(forScore: t.mediumMax + 1, size: size) == .hard)
        }
    }
}
