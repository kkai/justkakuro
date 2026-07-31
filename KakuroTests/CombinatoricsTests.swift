import Testing
@testable import Kakuro

@Suite struct CombinatoricsTests {

    @Test func digitSetBasics() {
        let mask = DigitSet.fromDigits([1, 5, 9])
        #expect(DigitSet.digits(mask) == [1, 5, 9])
        #expect(DigitSet.count(mask) == 3)
        #expect(DigitSet.sum(mask) == 15)
        #expect(DigitSet.contains(mask, 5))
        #expect(!DigitSet.contains(mask, 2))
        #expect(DigitSet.count(DigitSet.all) == 9)
    }

    @Test func knownCombinations() {
        #expect(SumCombinations.combinations(sum: 3, length: 2) == [DigitSet.fromDigits([1, 2])])
        #expect(SumCombinations.combinations(sum: 17, length: 2) == [DigitSet.fromDigits([8, 9])])
        #expect(SumCombinations.combinations(sum: 24, length: 3) == [DigitSet.fromDigits([7, 8, 9])])
        #expect(SumCombinations.combinations(sum: 6, length: 3) == [DigitSet.fromDigits([1, 2, 3])])
        // 2-cell 10 has four combinations: {1,9},{2,8},{3,7},{4,6}.
        #expect(SumCombinations.combinations(sum: 10, length: 2).count == 4)
        // 45 over 9 cells is the full set.
        #expect(SumCombinations.combinations(sum: 45, length: 9) == [DigitSet.all])
    }

    @Test func canonicalMagicBlocks() {
        let expectedMagic: [(sum: Int, length: Int)] = [
            (3, 2), (4, 2), (16, 2), (17, 2),
            (6, 3), (7, 3), (23, 3), (24, 3),
            (10, 4), (11, 4), (29, 4), (30, 4),
            (15, 5), (16, 5), (34, 5), (35, 5),
            (21, 6), (22, 6), (38, 6), (39, 6),
            (28, 7), (29, 7), (41, 7), (42, 7),
        ]
        for entry in expectedMagic {
            #expect(SumCombinations.isMagic(sum: entry.sum, length: entry.length),
                    "expected magic: \(entry.sum) in \(entry.length)")
        }
        #expect(!SumCombinations.isMagic(sum: 10, length: 2))
        #expect(!SumCombinations.isMagic(sum: 20, length: 3))
        // Length 8 and 9: every sum has at most one combination (missing-digit argument).
        for sum in 37...44 {
            #expect(SumCombinations.isMagic(sum: sum, length: 8))
        }
        #expect(SumCombinations.isMagic(sum: 45, length: 9))
    }

    @Test func partialRunFiltering() {
        // 3 cells summing 20 with a 9 placed: remaining combos must contain 9.
        let withNine = SumCombinations.combinations(sum: 20, length: 3, usedDigits: DigitSet.mask(9))
        #expect(!withNine.isEmpty)
        for combo in withNine {
            #expect(DigitSet.contains(combo, 9))
        }
        // Remaining union excludes the used digit itself.
        let union = SumCombinations.remainingUnion(sum: 20, length: 3, usedDigits: DigitSet.mask(9))
        #expect(!DigitSet.contains(union, 9))
        // 2 cells sum 17 with 8 placed: only 9 remains.
        let rest = SumCombinations.remainingUnion(sum: 17, length: 2, usedDigits: DigitSet.mask(8))
        #expect(DigitSet.digits(rest) == [9])
    }

    @Test func sumRanges() {
        #expect(SumCombinations.sumRange(length: 2) == 3...17)
        #expect(SumCombinations.sumRange(length: 9) == 45...45)
        #expect(SumCombinations.combinations(sum: 18, length: 2).isEmpty)
        #expect(SumCombinations.combinations(sum: 2, length: 2).isEmpty)
    }
}
