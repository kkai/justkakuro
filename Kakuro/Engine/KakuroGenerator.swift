import Foundation

/// Generates unique, band-matched Kakuro puzzles:
/// topology (symmetric block layout) → digit fill → uniqueness proof with
/// repair → logical-solvability grading → band matching.
nonisolated enum KakuroGenerator {

    struct Options: Sendable {
        var size: BoardSize
        var difficulty: Difficulty
        var seed: UInt64
        /// Extra condition a candidate must satisfy, checked against its solve
        /// histogram. Used by practice drills to ask for a board that actually
        /// exercises a given technique.
        ///
        /// The search already computes this histogram to grade difficulty, so
        /// filtering here scans candidates once instead of running the whole
        /// generator repeatedly and discarding the results. Evaluating it draws
        /// no randomness, so a default-accept caller sees the identical seeded
        /// stream and the identical board.
        var accepts: (@Sendable ([Technique: Int]) -> Bool)?

        init(size: BoardSize, difficulty: Difficulty,
             seed: UInt64 = UInt64.random(in: 0...UInt64.max),
             accepts: (@Sendable ([Technique: Int]) -> Bool)? = nil) {
            self.size = size
            self.difficulty = difficulty
            self.seed = seed
            self.accepts = accepts
        }
    }

    /// Generation budget knobs — tuned by GenerationPerformanceTests.
    /// The node budget is the real limiter; the topology cap is a backstop.
    private static let maxTopologyAttempts = 300
    private static let fillsPerTopology = 8
    private static let repairRoundsPerFill = 20

    /// How many off-band candidates to reject before settling for the nearest
    /// band. Small boards score in a narrow range, so a request needs several
    /// looks to land in the right tertile; they are also cheap enough to afford
    /// them. Large boards are the opposite on both counts.
    private static func maxCandidates(for size: BoardSize) -> Int {
        switch size {
        case .small: 24
        case .medium: 12
        case .large: 10
        }
    }
    /// Per-check node budget for the uniqueness prover; aborted checks reject
    /// the candidate so a pathological fill can't stall generation.
    private static let uniquenessNodeLimit = 40_000

    /// Deterministic work budget: total uniqueness-search nodes per generate call.
    /// Bounds worst-case latency without wall-clock nondeterminism.
    private static func nodeBudget(for size: BoardSize) -> Int {
        switch size {
        case .small: 600_000
        case .medium: 3_000_000
        case .large: 8_000_000
        }
    }

    /// Cancellation and progress, supplied by the caller. Both default to
    /// no-ops so every existing call site is unaffected.
    ///
    /// `isCancelled` is an explicit probe rather than a `Task.isCancelled` read
    /// inside the Engine: it keeps generation independent of task context and
    /// testable synchronously. Callers running inside a detached task pass
    /// `{ Task.isCancelled }` — the closure is *evaluated* on the generating
    /// task, which is what makes that read mean the right thing.
    struct Control: Sendable {
        var isCancelled: @Sendable () -> Bool = { false }
        /// Fraction of the node budget consumed, 0...1. Throttled — never
        /// called per node.
        var onProgress: @Sendable (Double) -> Void = { _ in }

        static let none = Control()
    }

    /// Always returns a shippable board: unique, logically solvable, graded.
    /// On cancellation it unwinds to the best-so-far or the baked fallback
    /// rather than returning nothing — "this result is no longer wanted" is the
    /// caller's knowledge, not the Engine's.
    static func generate(_ options: Options, control: Control = .none) -> GeneratedPuzzle {
        var rng = SeededRandomNumberGenerator(seed: options.seed)
        if let found = search(options, control: control, rng: &rng),
           let verified = verified(found, size: options.size) {
            return verified
        }
        return verifiedFallback(size: options.size, rng: &rng)
    }

    /// The search proper. Extracted verbatim from `generate` — **the RNG draw
    /// order must not change**, since band-match rates and the calibrated
    /// `DifficultyRater.thresholds` are a pure function of the seeded stream.
    private static func search(_ options: Options,
                               control: Control,
                               rng: inout SeededRandomNumberGenerator) -> KakuroPuzzle? {
        var best: (puzzle: KakuroPuzzle, distance: Int)? = nil
        var candidatesSeen = 0
        var rejected = 0
        let budget = nodeBudget(for: options.size)
        var nodesRemaining = budget
        var topologiesBuilt = 0
        var topologyAttempts = 0
        var lastReported = 0.0

        while topologiesBuilt < maxTopologyAttempts,
              topologyAttempts < maxTopologyAttempts * 12,
              nodesRemaining > 0,
              !control.isCancelled() {
            topologyAttempts += 1
            guard let mask = makeTopology(size: options.size, rng: &rng) else { continue }
            topologiesBuilt += 1
            for _ in 0..<fillsPerTopology {
                guard nodesRemaining > 0, !control.isCancelled() else { break }
                guard var grid = fill(mask: mask, difficulty: options.difficulty,
                                      control: control, rng: &rng) else { continue }
                // Random fills are almost never unique — repair toward
                // uniqueness by mutating cells where two found solutions differ,
                // pushing their runs toward low-combination sums.
                var puzzle = KakuroBuilder.puzzle(fromSolutionGrid: grid)
                var unique = false
                for _ in 0..<repairRoundsPerFill {
                    // The long pole: one repair round is bounded by
                    // uniquenessNodeLimit, so this is also the worst-case
                    // cancellation latency (~40k nodes).
                    if control.isCancelled() { break }
                    let uniqueness = BacktrackingSolver.countSolutions(
                        puzzle, limit: 2,
                        nodeLimit: min(uniquenessNodeLimit, max(nodesRemaining, 1)))
                    nodesRemaining -= uniqueness.nodesUsed
                    let fraction = 1 - Double(nodesRemaining) / Double(budget)
                    if fraction - lastReported >= 0.01 {
                        lastReported = fraction
                        control.onProgress(fraction)
                    }
                    if uniqueness.aborted { break }
                    if uniqueness.count == 1 {
                        unique = true
                        break
                    }
                    guard uniqueness.count == 2,
                          let mutated = mutate(grid: grid, mask: mask,
                                               solutions: uniqueness.solutions, rng: &rng)
                    else { break }
                    grid = mutated
                    puzzle = KakuroBuilder.puzzle(fromSolutionGrid: grid)
                }
                guard unique else { continue }
                let logical = LogicalSolver.solve(puzzle)
                // Hint guarantee: every shipped puzzle is fully solvable by
                // curriculum techniques.
                guard logical.solved else { continue }

                // A caller-supplied condition (drills asking for a board that
                // uses a particular technique). Rejected candidates are not
                // band candidates either, so they do not consume the band
                // budget — but they are counted, so an unsatisfiable request
                // gives up instead of grinding to the node limit.
                if let accepts = options.accepts, !accepts(logical.histogram) {
                    rejected += 1
                    if rejected >= maxCandidates(for: options.size) * 3 { return best?.puzzle }
                    continue
                }

                let score = DifficultyRater.score(profile: logical.histogram, solved: true)
                let band = DifficultyRater.band(forScore: score, size: options.size)
                if band == options.difficulty {
                    return puzzle
                }
                let distance = bandDistance(band, options.difficulty)
                if best == nil || distance < best!.distance {
                    best = (puzzle, distance)
                }
                candidatesSeen += 1
                if candidatesSeen >= maxCandidates(for: options.size), let best {
                    return best.puzzle
                }
            }
        }
        return best?.puzzle
    }

    /// The single gate every shipped board passes. Uniqueness and the hint
    /// guarantee (fully solvable by curriculum techniques) become runtime facts
    /// here rather than properties the search happens to maintain.
    ///
    /// This cannot reject a board the search returned: that board's in-loop
    /// proof already completed inside `uniquenessNodeLimit`, so re-walking the
    /// same finite tree reaches the same answer. It exists to cover the exits
    /// that had no proof at all — chiefly the baked fallback.
    private static func verified(_ puzzle: KakuroPuzzle, size: BoardSize) -> GeneratedPuzzle? {
        let uniqueness = BacktrackingSolver.countSolutions(puzzle, limit: 2, nodeLimit: 200_000)
        guard !uniqueness.aborted, uniqueness.count == 1 else { return nil }
        let logical = LogicalSolver.solve(puzzle)
        guard logical.solved else { return nil }
        let score = DifficultyRater.score(profile: logical.histogram, solved: true)
        return GeneratedPuzzle(puzzle: puzzle,
                               difficulty: DifficultyRater.band(forScore: score, size: size),
                               techniqueProfile: logical.histogram)
    }

    /// Deterministic last resort: the first baked grid that passes `verified`.
    /// Previously this shipped a baked board with no uniqueness check at all,
    /// and passed `logical.solved` to the rater instead of requiring it — an
    /// unsolvable grid would have shipped as a high-scoring "hard" puzzle the
    /// hint engine could not teach.
    static func verifiedFallback(size: BoardSize,
                                 rng: inout SeededRandomNumberGenerator) -> GeneratedPuzzle {
        let grids = bakedSolutions(for: size).shuffled(using: &rng)
        for grid in grids {
            if let verified = verified(KakuroBuilder.puzzle(fromSolutionGrid: grid), size: size) {
                return verified
            }
        }
        // Unreachable: bakedFallbacksAreUniqueAndSolvable proves every grid.
        assertionFailure("no baked \(size) fallback passed verification")
        let puzzle = KakuroBuilder.puzzle(fromSolutionGrid: grids[0])
        let logical = LogicalSolver.solve(puzzle)
        return GeneratedPuzzle(
            puzzle: puzzle,
            difficulty: DifficultyRater.band(
                forScore: DifficultyRater.score(profile: logical.histogram, solved: logical.solved),
                size: size),
            techniqueProfile: logical.histogram)
    }

    private static func bandDistance(_ a: Difficulty, _ b: Difficulty) -> Int {
        let order: [Difficulty] = [.easy, .medium, .hard]
        return abs(order.firstIndex(of: a)! - order.firstIndex(of: b)!)
    }

    // MARK: - Topology

    /// White-cell mask for the interior of a `dimension x dimension` grid.
    /// Row 0 and column 0 are always non-white (clue/block border).
    struct TopologyMask: Sendable, Hashable {
        let dimension: Int
        var white: Set<GridPosition>
    }

    /// Generates a valid, 180-degree symmetric topology, or nil if this attempt
    /// failed validation (caller retries with fresh randomness).
    static func makeTopology(size: BoardSize, rng: inout SeededRandomNumberGenerator) -> TopologyMask? {
        let d = size.dimension
        var white: Set<GridPosition> = []
        for r in 1..<d {
            for c in 1..<d {
                white.insert(GridPosition(row: r, col: c))
            }
        }
        // Target block density in the interior (excluding the mandatory border).
        // Bigger boards need denser blocks: short crossing runs are what make
        // uniqueness achievable.
        let densityRange: ClosedRange<Double> = switch size {
        case .small: 0.22...0.34
        case .medium: 0.26...0.38
        case .large: 0.34...0.44
        }
        let interior = (d - 1) * (d - 1)
        let targetBlocks = Int(Double(interior) * Double.random(in: densityRange, using: &rng))
        let twin: (GridPosition) -> GridPosition = { GridPosition(row: d - $0.row, col: d - $0.col) }

        var placed = 0
        var attempts = 0
        while placed < targetBlocks && attempts < interior * 4 {
            attempts += 1
            let r = Int.random(in: 1..<d, using: &rng)
            let c = Int.random(in: 1..<d, using: &rng)
            let pos = GridPosition(row: r, col: c)
            guard white.contains(pos) else { continue }
            white.remove(pos)
            white.remove(twin(pos))
            placed += 2
        }

        // Repair to fixpoint: blocking a violating cell (plus its twin, keeping
        // symmetry) only shrinks the white set, so this terminates. Cascading
        // new violations get picked up on the next iteration.
        let maxRun = maxRunLength(for: size)
        while let violation = firstStripViolation(dimension: d, white: white, maxRun: maxRun) {
            white.remove(violation)
            white.remove(twin(violation))
            if white.isEmpty { return nil }
        }
        guard isConnected(white: white) else { return nil }
        // Reject degenerate boards with too few cells for the size.
        guard white.count >= interior / 3 else { return nil }
        return TopologyMask(dimension: d, white: white)
    }

    /// Short runs are the backbone of solvable, unique Kakuro: capping run
    /// length keeps sums tight (more magic blocks) and ambiguity low.
    private static func maxRunLength(for size: BoardSize) -> Int {
        switch size {
        case .small: 4
        case .medium: 5
        case .large: 5
        }
    }

    /// Returns a cell in a strip of illegal length (1, or > maxRun), preferring
    /// length-1 orphans (blocking them is always a safe repair).
    private static func firstStripViolation(
        dimension d: Int, white: Set<GridPosition>, maxRun: Int = 9
    ) -> GridPosition? {
        var longStripCell: GridPosition? = nil
        // Horizontal strips.
        for r in 1..<d {
            var c = 1
            while c < d {
                if white.contains(GridPosition(row: r, col: c)) {
                    let start = c
                    while c < d, white.contains(GridPosition(row: r, col: c)) { c += 1 }
                    let len = c - start
                    if len == 1 { return GridPosition(row: r, col: start) }
                    if len > maxRun { longStripCell = GridPosition(row: r, col: start + len / 2) }
                } else { c += 1 }
            }
        }
        // Vertical strips.
        for c in 1..<d {
            var r = 1
            while r < d {
                if white.contains(GridPosition(row: r, col: c)) {
                    let start = r
                    while r < d, white.contains(GridPosition(row: r, col: c)) { r += 1 }
                    let len = r - start
                    if len == 1 { return GridPosition(row: start, col: c) }
                    if len > maxRun { longStripCell = GridPosition(row: start + len / 2, col: c) }
                } else { r += 1 }
            }
        }
        return longStripCell
    }

    private static func isConnected(white: Set<GridPosition>) -> Bool {
        guard let start = white.first else { return false }
        var seen: Set<GridPosition> = [start]
        var frontier = [start]
        while let pos = frontier.popLast() {
            for next in [
                GridPosition(row: pos.row - 1, col: pos.col),
                GridPosition(row: pos.row + 1, col: pos.col),
                GridPosition(row: pos.row, col: pos.col - 1),
                GridPosition(row: pos.row, col: pos.col + 1),
            ] where white.contains(next) && !seen.contains(next) {
                seen.insert(next)
                frontier.append(next)
            }
        }
        return seen.count == white.count
    }

    // MARK: - Uniqueness repair

    /// Changes one cell where the two found solutions differ, picking the
    /// replacement digit whose new run sums admit the fewest combinations.
    /// This directly attacks the ambiguity while keeping the fill valid.
    static func mutate(
        grid: [[Int?]], mask: TopologyMask,
        solutions: [[GridPosition: Int]], rng: inout SeededRandomNumberGenerator
    ) -> [[Int?]]? {
        guard solutions.count >= 2 else { return nil }
        // Sort before shuffling: Dictionary.keys order varies with the per-process
        // hash seed, so shuffling it directly would make generation
        // non-deterministic even with a seeded RNG.
        var differing = solutions[0].keys
            .filter { solutions[0][$0] != solutions[1][$0] }
            .sorted()
        differing.shuffle(using: &rng)

        for pos in differing {
            guard let current = grid[pos.row][pos.col] else { continue }
            // Digits already used in the cell's strips are off-limits.
            var taken: UInt16 = DigitSet.mask(current)
            for mate in stripMates(of: pos, in: mask) {
                if let d = grid[mate.row][mate.col] { taken |= DigitSet.mask(d) }
            }
            let replacements = DigitSet.digits(DigitSet.all & ~taken)
            guard !replacements.isEmpty else { continue }
            // Score each replacement by the combination count of the resulting
            // across+down sums — fewer combinations, tighter constraints.
            var best: (digit: Int, score: Int)? = nil
            for digit in replacements.shuffled(using: &rng) {
                var candidate = grid
                candidate[pos.row][pos.col] = digit
                let score = stripCombinationScore(grid: candidate, mask: mask, at: pos)
                if best == nil || score < best!.score {
                    best = (digit, score)
                }
            }
            guard let best else { continue }
            var result = grid
            result[pos.row][pos.col] = best.digit
            return result
        }
        return nil
    }

    private static func stripMates(of pos: GridPosition, in mask: TopologyMask) -> [GridPosition] {
        var mates: [GridPosition] = []
        for delta in [-1, 1] {
            var c = pos.col + delta
            while mask.white.contains(GridPosition(row: pos.row, col: c)) {
                mates.append(GridPosition(row: pos.row, col: c)); c += delta
            }
            var r = pos.row + delta
            while mask.white.contains(GridPosition(row: r, col: pos.col)) {
                mates.append(GridPosition(row: r, col: pos.col)); r += delta
            }
        }
        return mates
    }

    /// Total combination count of the two strips through `pos` (lower = tighter).
    private static func stripCombinationScore(
        grid: [[Int?]], mask: TopologyMask, at pos: GridPosition
    ) -> Int {
        var score = 0
        for horizontal in [true, false] {
            var cells: [GridPosition] = [pos]
            for delta in [-1, 1] {
                var p = pos
                while true {
                    p = horizontal
                        ? GridPosition(row: p.row, col: p.col + delta)
                        : GridPosition(row: p.row + delta, col: p.col)
                    guard mask.white.contains(p) else { break }
                    cells.append(p)
                }
            }
            guard cells.count >= 2 else { continue }
            let sum = cells.reduce(0) { $0 + (grid[$1.row][$1.col] ?? 0) }
            score += SumCombinations.combinations(sum: sum, length: cells.count).count
        }
        return score
    }

    // MARK: - Fill

    /// Assigns digits to the mask's white cells so no run repeats a digit.
    /// Digit ordering is biased by difficulty: extreme digits produce extreme
    /// sums (more magic blocks → easier); mid digits produce ambiguous sums.
    static func fill(
        mask: TopologyMask, difficulty: Difficulty,
        control: Control = .none, rng: inout SeededRandomNumberGenerator
    ) -> [[Int?]]? {
        let d = mask.dimension
        let positions = mask.white.sorted()
        // Precompute run membership: for each cell, the set of cells sharing
        // its horizontal and vertical strip.
        var stripMates: [GridPosition: [GridPosition]] = [:]
        for pos in positions {
            var mates: [GridPosition] = []
            for delta in [-1, 1] {
                var c = pos.col + delta
                while mask.white.contains(GridPosition(row: pos.row, col: c)) {
                    mates.append(GridPosition(row: pos.row, col: c)); c += delta
                }
                var r = pos.row + delta
                while mask.white.contains(GridPosition(row: r, col: pos.col)) {
                    mates.append(GridPosition(row: r, col: pos.col)); r += delta
                }
            }
            stripMates[pos] = mates
        }

        var assignment: [GridPosition: Int] = [:]
        // Rare fills backtrack pathologically; give up and let the caller
        // try a fresh one instead of grinding.
        var steps = 0
        let stepLimit = 60_000

        func digitOrder() -> [Int] {
            var digits = Array(1...9)
            digits.shuffle(using: &rng)
            switch difficulty {
            case .easy:
                // Prefer extremes: sort by distance from 5, descending, with the
                // shuffle as tiebreak. Extreme digits → extreme sums → magic blocks.
                return digits.sorted { abs($0 - 5) > abs($1 - 5) }
            case .medium, .hard:
                // Plain shuffle. A mid-digit bias for hard sounds right but
                // craters the uniqueness rate; hard candidates come from the
                // difficulty grading instead.
                return digits
            }
        }

        func recurse(_ index: Int) -> Bool {
            if index == positions.count { return true }
            steps += 1
            if steps > stepLimit { return false }
            // The other long pole. Gated so the probe costs nothing per node —
            // bailing here makes fill return nil and the caller `continue`, and
            // the outer probe then unwinds the search.
            if steps & 0x3FF == 0, control.isCancelled() { return false }
            let pos = positions[index]
            let taken = DigitSet.fromDigits(stripMates[pos]!.compactMap { assignment[$0] })
            for digit in digitOrder() where !DigitSet.contains(taken, digit) {
                assignment[pos] = digit
                if recurse(index + 1) { return true }
                assignment[pos] = nil
            }
            return false
        }
        guard recurse(0) else { return nil }

        var grid: [[Int?]] = Array(repeating: Array(repeating: nil, count: d), count: d)
        for (pos, digit) in assignment {
            grid[pos.row][pos.col] = digit
        }
        return grid
    }

    // MARK: - Fallback

    /// Used only when `generate` exhausts its node budget (or is cancelled).
    /// Randomised search is the wrong tool for a last-resort path — a Kakuro
    /// fill is almost never unique, so a template plus repair can churn for
    /// seconds and still hand back an ambiguous board. These grids were produced
    /// by `generate` and are re-proved at runtime by `verifiedFallback`, so the
    /// fallback is instant and always yields a puzzle the hint engine can teach.
    ///
    /// Verified solution grids, three per size. `nil` marks a non-white cell;
    /// clue sums are derived by `KakuroBuilder`.
    static func bakedSolutions(for size: BoardSize) -> [[[Int?]]] {
        switch size {
        case .small:
            return [
            [
                [nil, nil, nil, nil, nil, nil, nil],
                [nil, 5, 8, nil, nil, nil, nil],
                [nil, 7, 9, nil, nil, nil, nil],
                [nil, 3, 6, 9, 1, nil, nil],
                [nil, nil, nil, 1, 3, 5, 2],
                [nil, nil, nil, nil, nil, 1, 3],
                [nil, nil, nil, nil, nil, 2, 8],
            ],
            [
                [nil, nil, nil, nil, nil, nil, nil],
                [nil, 9, 7, nil, nil, nil, nil],
                [nil, 8, 6, nil, nil, nil, nil],
                [nil, 4, 3, 1, 2, nil, nil],
                [nil, nil, nil, 9, 7, 3, 6],
                [nil, nil, nil, nil, nil, 2, 1],
                [nil, nil, nil, nil, nil, 1, 3],
            ],
            [
                [nil, nil, nil, nil, nil, nil, nil],
                [nil, nil, nil, nil, nil, nil, nil],
                [nil, nil, nil, nil, 1, 9, 2],
                [nil, nil, nil, 1, 2, 8, 4],
                [nil, 3, 1, 2, 8, nil, nil],
                [nil, 1, 4, 3, nil, nil, nil],
                [nil, nil, nil, nil, nil, nil, nil],
            ],
            ]
        case .medium:
            return [
            [
                [nil, nil, nil, nil, nil, nil, nil, nil, nil],
                [nil, nil, nil, nil, nil, nil, nil, nil, nil],
                [nil, nil, nil, 7, 9, nil, nil, nil, nil],
                [nil, nil, nil, 9, 8, 2, nil, nil, nil],
                [nil, 9, 8, 6, nil, 6, 9, 2, 8],
                [nil, 6, 9, 2, 8, nil, 7, 1, 2],
                [nil, nil, nil, nil, 9, 1, 8, nil, nil],
                [nil, nil, nil, nil, nil, 3, 5, nil, nil],
                [nil, nil, nil, nil, nil, nil, nil, nil, nil],
            ],
            [
                [nil, nil, nil, nil, nil, nil, nil, nil, nil],
                [nil, nil, nil, nil, nil, nil, nil, nil, nil],
                [nil, nil, nil, 3, 1, nil, nil, nil, nil],
                [nil, nil, nil, 7, 9, 8, nil, nil, nil],
                [nil, 9, 5, 8, nil, 9, 1, 2, 3],
                [nil, 7, 6, 9, 8, nil, 9, 1, 6],
                [nil, nil, nil, nil, 1, 2, 7, nil, nil],
                [nil, nil, nil, nil, nil, 1, 8, nil, nil],
                [nil, nil, nil, nil, nil, nil, nil, nil, nil],
            ],
            [
                [nil, nil, nil, nil, nil, nil, nil, nil, nil],
                [nil, nil, nil, nil, nil, nil, nil, nil, nil],
                [nil, nil, nil, nil, 9, 1, nil, nil, nil],
                [nil, nil, nil, 1, 8, 9, nil, 9, 1],
                [nil, 6, 9, 8, nil, 2, 9, 7, 8],
                [nil, 9, 7, 6, 8, nil, 1, 4, 2],
                [nil, 2, 8, nil, 1, 3, 2, nil, nil],
                [nil, nil, nil, nil, 2, 1, nil, nil, nil],
                [nil, nil, nil, nil, nil, nil, nil, nil, nil],
            ],
            ]
        case .large:
            return [
            [
                [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil],
                [nil, nil, nil, nil, nil, nil, 9, 6, 5, nil, nil],
                [nil, nil, nil, nil, nil, nil, 7, 4, 8, nil, nil],
                [nil, nil, nil, nil, nil, nil, nil, 9, 7, nil, nil],
                [nil, nil, nil, nil, nil, nil, nil, 8, 9, 7, 2],
                [nil, nil, nil, nil, nil, 9, 6, 7, nil, 9, 1],
                [nil, 2, 1, nil, 9, 7, 8, nil, nil, nil, nil],
                [nil, 1, 9, 2, 8, nil, nil, nil, nil, nil, nil],
                [nil, nil, nil, 9, 7, nil, nil, nil, nil, nil, nil],
                [nil, nil, nil, 1, 5, 3, nil, nil, nil, nil, nil],
                [nil, nil, nil, 4, 3, 1, nil, nil, nil, nil, nil],
            ],
            [
                [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil],
                [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil],
                [nil, nil, nil, nil, 1, 5, nil, nil, nil, nil, nil],
                [nil, nil, nil, nil, 9, 7, 3, nil, nil, nil, nil],
                [nil, nil, nil, nil, nil, 8, 1, 9, nil, 8, 9],
                [nil, nil, 4, 7, 9, 3, nil, 1, 9, 3, 2],
                [nil, 7, 2, 9, 8, nil, 1, 2, 8, 9, nil],
                [nil, 9, 1, nil, 1, 9, 2, nil, nil, nil, nil],
                [nil, nil, nil, nil, nil, 8, 9, 2, nil, nil, nil],
                [nil, nil, nil, nil, nil, nil, 8, 1, nil, nil, nil],
                [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil],
            ],
            [
                [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil],
                [nil, nil, nil, nil, nil, nil, nil, nil, 9, 7, nil],
                [nil, nil, nil, nil, nil, nil, nil, 9, 8, 3, nil],
                [nil, nil, nil, nil, nil, nil, 1, 8, nil, 9, 8],
                [nil, nil, nil, nil, 1, 3, 2, 7, nil, 2, 9],
                [nil, nil, nil, nil, 2, 1, 8, nil, nil, nil, nil],
                [nil, nil, nil, nil, nil, 2, 4, 1, nil, nil, nil],
                [nil, 1, 3, nil, 1, 5, 3, 2, nil, nil, nil],
                [nil, 3, 7, nil, 9, 7, nil, nil, nil, nil, nil],
                [nil, nil, 1, 9, 2, nil, nil, nil, nil, nil, nil],
                [nil, nil, 2, 1, nil, nil, nil, nil, nil, nil, nil],
            ],
            ]
        }
    }
}
