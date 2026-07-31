import Foundation

/// Digit sets are represented as UInt16 bitmasks: bit n set means digit n is present (bits 1...9).
nonisolated enum DigitSet {
    static let all: UInt16 = 0b11_1111_1110  // digits 1...9

    static func mask(_ digit: Int) -> UInt16 {
        1 << digit
    }

    static func contains(_ mask: UInt16, _ digit: Int) -> Bool {
        mask & (1 << digit) != 0
    }

    static func digits(_ mask: UInt16) -> [Int] {
        (1...9).filter { mask & (1 << $0) != 0 }
    }

    static func count(_ mask: UInt16) -> Int {
        mask.nonzeroBitCount
    }

    static func sum(_ mask: UInt16) -> Int {
        digits(mask).reduce(0, +)
    }

    static func fromDigits(_ digits: some Sequence<Int>) -> UInt16 {
        digits.reduce(0) { $0 | (1 << $1) }
    }
}

/// Precomputed Kakuro sum combinations. A combination is a set of distinct digits 1-9
/// (as a UInt16 bitmask) of a given size summing to a given total.
nonisolated enum SumCombinations {
    /// table[length][sum] = all digit-set bitmasks of `length` distinct digits summing to `sum`.
    private static let table: [[[UInt16]]] = {
        var result = Array(repeating: Array(repeating: [UInt16](), count: 46), count: 10)
        for mask in 0..<1024 {
            let m = UInt16(mask) & DigitSet.all
            guard m == UInt16(mask), m != 0 else { continue }
            let length = DigitSet.count(m)
            let sum = DigitSet.sum(m)
            result[length][sum].append(m)
        }
        return result
    }()

    /// All combinations for a run of `length` cells summing to `sum`.
    static func combinations(sum: Int, length: Int) -> [UInt16] {
        guard (2...9).contains(length), (1...45).contains(sum) else { return [] }
        return table[length][sum]
    }

    /// Combinations still possible given digits already placed in the run and cells remaining.
    /// `usedDigits` must be a subset of the returned combinations; remaining cells get the rest.
    static func combinations(sum: Int, length: Int, usedDigits: UInt16) -> [UInt16] {
        combinations(sum: sum, length: length).filter { $0 & usedDigits == usedDigits }
    }

    /// Union of all digits usable anywhere in a run (before positional constraints).
    static func union(sum: Int, length: Int) -> UInt16 {
        combinations(sum: sum, length: length).reduce(0, |)
    }

    /// Union of digits usable in the *remaining* cells of a partially filled run.
    static func remainingUnion(sum: Int, length: Int, usedDigits: UInt16) -> UInt16 {
        combinations(sum: sum, length: length, usedDigits: usedDigits)
            .reduce(UInt16(0)) { $0 | ($1 & ~usedDigits) }
    }

    /// A "magic block": exactly one digit combination exists for this (sum, length).
    static func isMagic(sum: Int, length: Int) -> Bool {
        combinations(sum: sum, length: length).count == 1
    }

    /// Minimum and maximum possible sums for `length` distinct digits.
    static func sumRange(length: Int) -> ClosedRange<Int> {
        let minSum = (1...length).reduce(0, +)
        let maxSum = ((10 - length)...9).reduce(0, +)
        return minSum...maxSum
    }
}
