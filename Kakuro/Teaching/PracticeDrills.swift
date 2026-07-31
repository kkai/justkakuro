import Foundation

/// Drill boards for practicing one technique: small generated puzzles whose
/// logical solve is known to use the target technique. Deterministic seeds per
/// technique keep drills stable across launches.
nonisolated enum PracticeDrills {

    /// Finds a small puzzle whose solve trace uses `technique` at least once
    /// (twice for the basics). Seeded search, so the result is reproducible.
    static func drillPuzzle(for technique: Technique, variant: UInt64 = 0) -> GeneratedPuzzle {
        let minUses = technique <= .crossReference ? 2 : 1
        var fallback: GeneratedPuzzle? = nil
        // Deterministic seed stream per (technique, variant).
        let base = 0x00D5_1000 &+ UInt64(technique.rawValue) &* 977 &+ variant &* 7919
        for offset: UInt64 in 0..<24 {
            let candidate = KakuroGenerator.generate(
                .init(size: .small,
                      difficulty: technique >= .combinationReduction ? .hard : .medium,
                      seed: base &+ offset))
            let uses = candidate.techniqueProfile[technique] ?? 0
            if uses >= minUses {
                return candidate
            }
            if uses > 0, fallback == nil {
                fallback = candidate
            }
        }
        // A drill that exercises the technique once beats no drill at all.
        return fallback ?? KakuroGenerator.generate(.init(size: .small, difficulty: .easy, seed: base))
    }
}
