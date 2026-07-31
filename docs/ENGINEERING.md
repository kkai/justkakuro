# Engineering notes

Working notes: architecture, invariants, and the things that have already gone wrong once.

## Project Overview

Kakuro is an iPhone/iPad puzzle game (iOS 18+) that teaches players how to play Kakuro, modeled on Zach Gage's *Good Sudoku*: an interactive rules tutorial, a technique curriculum, a context-aware hint engine that explains techniques (not just answers), per-technique practice drills with mastery tracking, and busywork reduction (auto-notes, tap-a-clue combinations, digit highlighting).

### Kakuro rules
White cells form horizontal/vertical runs. Each run's clue (diagonal-split clue cell: top-right = across, bottom-left = down) is the sum of its digits. Digits 1–9 only; no digit repeats within a run. Exactly one solution per puzzle.

### Technique curriculum (order = source of truth)
`Technique` enum: duplicateInRun → magicBlock → crossReference → minMaxBounds → nakedSingle → hiddenSingle → combinationReduction → surplusDeficit. This order drives the solver loop, difficulty grading, hint escalation, tutorial sequence, and practice menu.

## Build & Test

```bash
# Build
xcodebuild -project Kakuro.xcodeproj -scheme Kakuro -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' build

# Tests (Swift Testing framework, KakuroTests target hosted by the app)
xcodebuild test -project Kakuro.xcodeproj -scheme Kakuro -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5'

# iPad
xcodebuild test -project Kakuro.xcodeproj -scheme Kakuro -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M4),OS=18.5'
```

Always pin `OS=` in destinations — this machine has iOS 18.x and 26.x runtimes and an unpinned name matches multiple simulators.

## Architecture

Single Xcode project, objectVersion 77 with `PBXFileSystemSynchronizedRootGroup` — **new Swift files under `Kakuro/` and `KakuroTests/` are picked up automatically; never edit project.pbxproj to add files.**

- `Kakuro/App/` — @main, ContentView, `Route` enum navigation
- `Kakuro/Engine/` — pure logic, **no SwiftUI imports, all `nonisolated` value types (Sendable)**. Models, `SumCombinations` (UInt16 digit-bitmask combination table), `LogicalSolver` (human-technique solver; `nextStep(puzzle:board:)` powers hints), `BacktrackingSolver` (`countSolutions(limit:2)` uniqueness proof only), `KakuroGenerator`, `Difficulty`
- `Kakuro/Game/` — `KakuroGame` (@Observable @MainActor; `init(size:difficulty:)` generates, `init(puzzle:)` injects for tests/tutorial) + game views
- `Kakuro/Teaching/` — `HintEngine` (nudge → technique → highlight → resolution escalation), tutorial script DSL + fixture puzzles, practice drills, `MasteryTracker`
- `Kakuro/Design/` — `Theme` (semantic colors), `Motion` (named spring tokens only — no inline animation values), `Haptics`
- `Kakuro/Persistence/` — `ProgressStore` (@Observable, UserDefaults + Codable, versioned keys `kakuro.*.v1`, `init(userDefaults:)` seam for tests)

## Conventions

- Swift 6, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` project-wide; Engine types are explicitly `nonisolated` so generation runs off-main
- Model-View pattern, **no ViewModels**; `@Observable` (never ObservableObject/@Published); `@Environment` for services; view state as enums; `.task(id:)` for async effects
- `struct` over `class`; classes `final`; no force unwraps
- Invariants: every shipped puzzle must be 100% solvable by `LogicalSolver` (hint guarantee — enforced in `KakuroGenerator.generate`); candidate sets are `UInt16` bitmasks throughout the engine; the `BacktrackingSolver` hot path (`candidates(at:)`) must stay allocation-free (arrays/filter/reduce there cost ~7µs/node vs ~1µs)
- Difficulty band thresholds in `Difficulty.swift` are p33/p66 tertiles over generated candidates per size. Recalibrate whenever generation, density, or rater weights change

## Generation architecture notes (learned the hard way)

- Random Kakuro fills are ~never unique (0/50 on 7x7). Uniqueness comes from `mutate()`: find where two solutions differ, change that cell's digit toward low-combination sums, re-check. ~34% of small fills converge within 20 rounds
- Denser blocks + capped run lengths (4/5/5 per size) are what make medium/large generation viable — long runs are ambiguity factories
- `generate()` is bounded by a deterministic **node budget** (0.6M/3M/8M per size), not attempt counts; a wall-clock deadline would break per-seed determinism that `GenerationTests` asserts
- Band-match rate is governed by `maxCandidates(for:)` — how many off-band candidates to reject before settling for the nearest band. It was a flat 4 and gave ~55% match; per-size (24/12/10) gives 19–20/20 at every size and barely moves latency (small worst 0.14s, large worst ~6s)
- The fallback path (budget exhausted) ships **pre-verified solution grids**, three per size, not a template plus repair. Searching there is the wrong tool: a Kakuro fill is almost never unique, so the old template loop could churn ~14s on medium and still return an ambiguous board. `bakedFallbacksAreUniqueAndSolvable` re-proves the shipped grids
- Native -O timings: small ~0.03s, medium ~0.3s, large 1–2s (worst ~7s). Debug simulator is ~5x slower — perf-test budgets account for that
- Fast engine iteration without the simulator: compile the engine into a CLI binary —
  `swiftc -O -o bench Kakuro/Engine/*.swift main.swift` (Engine has no UIKit/SwiftUI imports; keep it that way). Write benchmark output to stderr (stdout is block-buffered under a pipe)

## Actor isolation in `Kakuro/Design/`

The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so **every unannotated type is `@MainActor`** — including closures it hands to UIKit.

- `Theme` and `Motion` are **`nonisolated`**, and that is load-bearing. `UIColor.init(dynamicProvider:)` is imported without `NS_SWIFT_SENDABLE`, so a closure literal passed to it inherits MainActor isolation and Swift 6 emits an executor assertion in its prologue. UIKit resolves dynamic colors on `com.apple.SwiftUI.AsyncRenderer`, so that assertion trips and the app traps (`EXC_BREAKPOINT`). It shipped this way and crashed **intermittently, anywhere** — including idle on Home — because whether a given resolve lands off-main is a race.
- `Haptics` is `@MainActor` and must stay so (`UIFeedbackGenerator` is `NS_SWIFT_UI_ACTOR`; `enabled` is mutable global state).
- **Never hand a closure to an unannotated UIKit API from MainActor-isolated code.** Mark the type `nonisolated` *and* the closure `@Sendable`.
- Guarded three ways by `ThemeIsolationTests`: a compile-time guard (`nonisolated` helpers that fail the *build* if the annotation is lost), a runtime guard resolving every color off-main, and a source scan that fails if a dynamic provider appears outside `Theme.swift`.

## View identity: a screen must outlive the state that created it

`ContentView`'s `.resumeGame` destination used to read `progress.savedGame` inline. Once that became observable, winning — which clears the save — invalidated the destination and swapped the live game for `MissingSaveView` *mid-celebration*, so the win sheet never appeared. `ResumeGameView` now resolves the snapshot **once** on appear. Resolve navigation input into `@State` at entry; don't re-derive a screen's existence from mutable state it will itself mutate.

## Persistence invariants

- The saved game must be written **as the player works** (`GameView.persist()` on board change, scene backgrounding, and disappear). Saving only on `game.phase` change silently loses everything: a game that is started and never paused never changes phase
- `ProgressStore.savedGame` is observable state, not a UserDefaults read. A view body that calls `defaults.object(forKey:)` never invalidates, so the Continue card would not appear until the app was relaunched
- Covered by `savedGameIsVisibleImmediatelyAndAfterRelaunch`; both halves regressed independently

## End-to-end verification in the simulator

Unit tests cannot reach view lifecycle (save triggers, layout, contrast), and both persistence bugs above survived a green suite. To drive the app:

```bash
python3 -m venv venv && venv/bin/pip install fb-idb   # idb_companion is already on this machine
venv/bin/idb connect <udid>
venv/bin/idb ui describe-all --udid <udid>            # accessibility tree = element coordinates + VoiceOver check
venv/bin/idb ui tap --udid <udid> <x> <y>             # coordinates are POINTS, not pixels
```

**Drive from a single Python process, not a shell loop.** Chained `idb ui tap` calls in one Bash invocation drop taps; the same taps issued via `subprocess` from one Python script land reliably (16 in a row, verified). An earlier note here claimed "only the first tap per shell invocation registers" and blamed idb — that was mostly the Theme isolation crash killing the app mid-sequence. Both effects exist; the Python driver avoids both.

**Confirm every tap from the tree, and check liveness separately.** A dropped tap and a dead app look identical from the outside. After each tap re-read `describe-all` and assert the label changed; check `xcrun simctl spawn <udid> launchctl list | grep -i kakuro` for liveness, and diff `~/Library/Logs/DiagnosticReports/` (note: reports get rotated into `Retired/`) for new `.ips` files.

**`KakuroGame.tap()` toggles selection.** Tapping an already-selected cell *deselects* it, so the next digit press is a no-op. A driver that re-taps a cell it already selected will look like the app is ignoring input.

**Getting a puzzle's solution:** read the app's own save — `xcrun simctl get_app_container <udid> de.kaikunze.kakuro data` → `Library/Preferences/de.kaikunze.kakuro.plist` → `plistlib` → `json.loads(pl["kakuro.saveGame.v1"])` → `generated.puzzle.cells[r][c].white.solution`. The save only exists after a board change or a backgrounding, and `[GridPosition: Int]` encodes as a **flat alternating array**, not an object. Read while booted (cfprefsd serves the live value); only *write* with the sim shut down.

## Calibration workflow

1. Build a CLI bench (above) that loops `makeTopology` → `fill` → mutate-repair → `LogicalSolver.solve`, collecting `DifficultyRater.score` for 30+ unique+solvable candidates per size
2. Paste p33/p66 into `DifficultyRater.thresholds`
3. Re-run `GenerationTests` (band-match assertions are intentionally loose — 60% — since `generate` returns nearest-band on budget exhaustion)

## Project Configuration

- Bundle ID: `de.kaikunze.kakuro` · Team: `8H42EZRCCP`
- iOS 18.0+, iPhone + iPad (`TARGETED_DEVICE_FAMILY = 1,2`), portrait on iPhone, all orientations on iPad

