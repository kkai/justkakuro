# Engineering notes

Working notes: architecture, invariants, and the things that have already gone wrong once.

## Project Overview

Just Kakuro is an iPhone/iPad puzzle game (iOS 18+) that teaches players how to play Kakuro, modeled on Zach Gage's *Good Sudoku*: an interactive rules tutorial, a technique curriculum, a context-aware hint engine that explains techniques (not just answers), per-technique practice drills with mastery tracking, and busywork reduction (auto-notes, tap-a-clue combinations, digit highlighting).

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

Two known test-environment quirks:
- Simulator **cloning for parallel testing intermittently fails** ("Device was allocated but was stuck in creation state"), and killing `CoreSimulatorService` does not always clear it. Fall back to `-destination 'id=<udid>' -parallel-testing-enabled NO`.
- `ThemeIsolationTests.dynamicColorsResolveOffTheMainThread` **fails under serial (non-cloned) runs** and passes under cloned parallel runs — the `UIColor(Color)` round-trip loses its dynamic provider without a fresh host environment. This is pre-existing and unrelated to app code; verified by stashing all changes and re-running. Do not "fix" the Theme code because of it.

## Architecture

Single Xcode project, objectVersion 77 with `PBXFileSystemSynchronizedRootGroup` — **new Swift files under `Kakuro/` and `KakuroTests/` are picked up automatically; never edit project.pbxproj to add files.**

- `Kakuro/App/` — @main, ContentView, `Route` enum navigation
- `Kakuro/Engine/` — pure logic, **no SwiftUI imports, all `nonisolated` value types (Sendable)**. Models, `SumCombinations` (UInt16 digit-bitmask combination table), `LogicalSolver` (human-technique solver; `nextStep(puzzle:board:)` powers hints), `BacktrackingSolver` (`countSolutions(limit:2)` uniqueness proof only), `KakuroGenerator`, `Difficulty`
- `Kakuro/Game/` — `KakuroGame` (@Observable @MainActor; `init(size:difficulty:)` generates, `init(puzzle:)` injects for tests/tutorial) + game views
- `Kakuro/Teaching/` — `HintEngine` (nudge → technique → highlight → resolution escalation), tutorial script DSL + fixture puzzles, practice drills, `MasteryTracker`
- `Kakuro/Design/` — `Theme` (semantic colors), `Motion` (named spring tokens only — no inline animation values), `Haptics`
- `Kakuro/Persistence/` — `ProgressStore` (@Observable, UserDefaults + Codable, versioned keys `kakuro.*.v1`, `init(userDefaults:)` seam for tests)
- `Kakuro/Store/` — the one-time unlock. `FeatureGate` (all gating as pure `nonisolated` functions — no StoreKit, exhaustively tested), `EntitlementStore` (@Observable, StoreKit behind an `EntitlementSource` protocol seam), `PaywallPresenter` + `PaywallView` + `LockedFeatureView`

## Monetization

One non-consumable, `de.kaikunze.kakuro.full`, $4.99. No ads, no subscription. ASC IAP id `6796737529`.

**Free:** Learn lessons 1–3 (rules / No Repeats / Magic Blocks), small + medium boards, every difficulty on them, and the "something here is wrong" error hint.
**Paid:** lessons 4–9, all Practice drills, mastery *display*, the escalating `HintEngine` ladder, large boards, Stats.

- **All gating decisions live in `FeatureGate`**, not scattered through views. Add a gate there and call it; `EntitlementTests` asserts the free set exactly, so a drifted gate fails a test rather than shipping.
- **`Transaction.currentEntitlements` is authoritative; `kakuro.entitlement.v1` is a display hint** so the first frame after a cold launch doesn't show locks to somebody who paid. `EntitlementSource.isOwned` returns `Bool?` — **`nil` means "couldn't determine" and must never downgrade**, or offline players lose what they bought. Read the comment on `Key.unlocked` before changing any of this.
- The `Transaction.updates` listener starts in `EntitlementStore.init`, not a view's `.task` — it has to be live before any transaction completes.
- **Gate the mastery display, not `MasteryTracker` itself.** It keeps recording for free players; showing an empty progress path to someone who just paid would punish the purchase.
- **Withholding a hint must not call `mastery.recordHint`** — that would silently damage the player's progress path for a hint they never saw. `HintPolicy` defaults to `.full` so existing `HintEngineTests` call sites are untouched.
- Paywalled rows stay **tappable** (they present the paywall); only mastery-locked rows are `.disabled`. A dead row neither teaches nor sells.
- Simulator testing: `StoreKit/Kakuro.storekit`, wired via the **shared** scheme at `Kakuro.xcodeproj/xcshareddata/xcschemes/Kakuro.xcscheme` (`<StoreKitConfigurationFileReference>`). Keep the config outside `Kakuro/` — the synchronized root group would otherwise ship it inside the app bundle. Note the scheme's `<TestAction>` must not contain an empty `<TestPlans>` element; that makes xcodebuild report "not configured for the test action".

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

## Tutorial lessons: bake the early curriculum

`TutorialPuzzles.bakedTechniques` is the source of truth for which lessons have a hand-authored board and script; `TutorialFixtureTests` iterates it, so the list cannot drift.

Lesson 2 (`duplicateInRun`) used to fall through to `generatedLesson` → `PracticeDrills.drillPuzzle`, which runs **up to 25 serial `KakuroGenerator.generate` calls** — measured at **0.66s native -O**, so ~3.3s in a debug simulator and worse on older hardware. It also *never succeeded*: all 24 seeded attempts failed the `duplicateInRun >= 2` filter and it returned the easy fallback, a 12-cell board with a `duplicateInRun` count of **zero**. The lesson teaching No Repeats shipped a board that never needs No Repeats. `earlyLessonsAreBakedNotGenerated` guards the class of regression; `bakedLessonsLoadPromptly` is the loose timing backstop.

Two things to know when authoring a lesson board:

- **`duplicateInRun` does not appear in a from-empty `LogicalSolver` trace.** Its detector needs a digit already placed, and `magicBlock`/`crossReference` reach the same cells first. Judge a No-Repeats board by the trace *after* the scripted entries (`noRepeatExamStaysInsideTheCurriculum` does), not by `techniqueProfile`.
- Verify uniqueness with the engine before writing any copy around a board — `swiftc -O -o bench Kakuro/Engine/*.swift main.swift`, then `BacktrackingSolver.countSolutions(puzzle, limit: 2).count == 1`. Small boards are very often ambiguous.

Lessons 4–9 still generate. They are all paid, so **the first thing a paying customer opens is the slowest screen in the app** — worth baking next, or at minimum routing through `PuzzleCache` with real progress instead of an indefinite spinner.

`TutorialEngine.advance()` clears `notesMode` when entering `.solveFreely`. Without it, a preceding `.requireNote` step left notes mode on, every digit the player entered in the exam became a note, and the board could never reach `.won` — Cross Reference was uncompletable. `tutorialEngineWalksBakedLesson` covers every baked lesson now; the old test only ever walked the rules lesson, which has no `.solveFreely` step.

## Puzzle delivery: warm one key, await it, never race it

`PuzzleCache` stores **tasks, not finished puzzles** (`entries: [CacheKey: Entry]`, each holding a `Task<GeneratedPuzzle?, Never>`). That is the whole design: a claim on a key that is already generating *awaits that task*. The previous split of `cache` + `inFlight` let `takePuzzle` miss the cache and start a **second** generation while the first ran, so the player waited on the one that started later and the first board was discarded. With one table the race cannot be expressed.

- `warm(size:difficulty:)` — speculative, `.utility`, cancels any **other running unclaimed** entry. At most one speculative generation at a time: nine concurrent ones (the old picker-mash behaviour) starve the cooperative pool and slow the board the player is actually waiting for.
- `request(size:difficulty:) -> PuzzleRequest` — claims the key, returning the progress stream **and** the handle in one synchronous call. Splitting them puts a suspension point where progress is missed or the entry is rebuilt underneath.
- **A cancelled entry must be removed from the table.** It resolves to `nil` forever, so leaving it makes every later request for that key hang. Not an optimization — `cancellingDropsTheEntrySoALaterRequestStartsFresh` pins it.
- **Identity-guard every `entries[key]` write** (`entries[key] === entry`); that is why `Entry` is a `final class`. A late-finishing task must not clobber a fresher entry.
- Cancellation reaches the generator via `withTaskCancellationHandler` in `PuzzleRequest.puzzle()`. Bind the `Task` to a local first — `onCancel` is `@Sendable` and may run off-main, so it cannot capture the MainActor-isolated `Entry`.
- `init(generate:)` is the test seam. `PuzzleCacheTests` had to be written from scratch; the absence of any test here is how the double-generation bug shipped.

Warming policy lives in `HomeView`, not `ContentView`: it warms the key the pickers point at, restored from `ProgressStore.lastPlayed`. **`isRestoring` is load-bearing** — assigning `newGameSize` fires the size gate, and at launch `entitlements.isUnlocked` can still be false, so restoring a large board would show a paying customer a paywall on cold launch.

### Generation cost, measured (native -O; debug simulator ≈5×)

| | easy | medium | hard |
|---|---|---|---|
| medium | p50 0.16s, p95 1.79s | p50 0.19s, p95 0.84s | p50 0.44s, p95 1.51s |
| large | **p50 2.38s, max 7.00s** | p50 0.97s, max 3.78s | p50 0.28s, max 1.66s |

**Hard is not slower than medium** — `fill`'s digit ordering only special-cases `.easy`, so `.medium` and `.hard` take byte-identical search paths. **Easy is the expensive band**, and `large/easy` is the worst case in the app. The `.easy` extreme-digit bias is why: removing it makes large/easy ~2× faster with no band-accuracy loss, but makes *medium* slower. It is size-dependent; do not touch it without a calibration run.

## Uniqueness is a runtime guarantee, not a convention

`generate` has exactly one exit, and everything passes `verified(_:size:)`: `countSolutions(limit: 2, nodeLimit: 200_000)` requiring `!aborted && count == 1`, then `LogicalSolver.solve` requiring `.solved`. Measured cost **17ms p50 / 84ms max on large — 0.7% of a 2.4s generation**.

Before this, the budget-exhausted fallback returned a baked grid with **no uniqueness check at all**, and passed `logical.solved` to the rater instead of requiring it — an unsolvable grid would have shipped as a high-scoring "hard" puzzle the hint engine could not teach. `verifiedFallback` now returns the first baked grid that passes.

`search(_:control:rng:)` is the old loop moved **verbatim**. **Never reorder or add an RNG draw there** — band-match rates and the calibrated `DifficultyRater.thresholds` are a pure function of the seeded stream. The check that this held: band-miss counts per (size, difficulty) were identical before and after the extraction.

`KakuroGenerator.Control` carries `isCancelled` and `onProgress`. The probe is explicit rather than a `Task.isCancelled` read inside the Engine, so generation stays independent of task context; callers pass `{ Task.isCancelled }`, which is *evaluated* on the generating task. Probes sit at cold sites only — the outer loop, the repair loop, and `fill`'s recursion gated at `steps & 0x3FF`. **Never probe inside `BacktrackingSolver.candidates(at:)`**; that path is pinned allocation-free at ~1µs/node.

## Three techniques never appear in a solve trace

Measured across 108 generated boards spanning every size and difficulty:
`duplicateInRun`, `hiddenSingle` and `surplusDeficit` appear in **zero** of them
(`combinationReduction` appears in only 16). The detectors ahead of them in
curriculum order always reach the same cells first — a placement already strips
the digit from its run-mates' candidates, so the dedicated no-repeat step never
has work, and the cheap eliminations finish the board before the arithmetic ones
are consulted.

Consequences, all of which bit at once:

- Their Practice drills cannot be found by search. `drillPuzzle` used to run 25
  generations and then hand back a board with **zero** uses of the technique it
  advertised. Those three now use hand-authored boards (`PracticeDrills.bakedGrids`);
  `PracticeDrills.handAuthored` is the source of truth and the tests iterate it.
- `MasteryTracker.recordEntry` credits the hardest technique in the deduction
  chain, so these three can never be credited through play either. Their only
  route to `.learned` is `recordDrillCompleted`, which is why the baked drills
  matter beyond load time.
- `TechniqueRecapView` will never list them on a win sheet.

`PracticeDrillTests.handAuthoredTechniquesAreUnsearchable` pins the premise: if
it starts failing, detector precedence changed and these could go back to being
searched. Everything else uses `Options.accepts`, a predicate checked against the
solve histogram inside the search, which replaced 24 generate-and-discard rounds
with one filtered search (measured 0.004–0.115s, from up to 1.23s).

## The privacy manifest must contain no comments

`Kakuro/PrivacyInfo.xcprivacy` declares one required-reason API: `UserDefaults`
under reason `CA92.1`, meaning the app reads and writes only its own defaults and
nothing leaves the device. `ProgressStore` keeps settings, stats, best times,
mastery and the saved game; `EntitlementStore` caches the purchase flag so a
paying customer does not see locks on the first frame after launch.

That explanation lives here rather than in the file. Build 2 shipped with an XML
comment inside the `NSPrivacyAccessedAPIReasons` array and was rejected with
**ITMS-91056, invalid privacy manifest**. Neither `plutil -lint` nor
`altool --validate-app` catches it: the manifest is valid property list, and
Apple's privacy-manifest validator runs later during processing. Keep the file to
documented keys and string values only.

## Statistics invariants

- **Background = paused.** `GameView` pauses on `scenePhase` leaving `.active`.
  `tick` adds a wall-clock delta and `Task.sleep` is on a continuous clock, so
  without this an overnight background folded ~8 hours into `elapsed`, inflating
  lifetime play time and poisoning first best times.
- **Solves are filed under the *requested* difficulty**, via
  `KakuroGame.difficultyForRecords`. `generate` returns the nearest band when its
  budget runs out, and everything else (`PuzzleCache`, `Route`, `recordLastPlayed`)
  keys on the request; stats used to key on the delivered band, so a best time
  could land in a column the player never chose. `Snapshot.requestedDifficulty`
  is optional so older saves still decode.
- **Only the player earns mastery.** `recordEntry` takes `unaided:` because it
  cannot infer it: a digit placed by tapping Apply on a hint looks identical from
  the board state. `KakuroGame.claimMasteryCredit(at:)` makes each cell pay out
  once per game, so place/undo/replace cannot farm credit.
- Time formatting lives in `TimeFormatting`, not in three private view copies.
  The copies are why a 72-minute solve rendered "72:14" and a first solve under a
  minute rendered "0m played".

## Driving the app: two traps that fake a pass

- The segmented size/difficulty pickers expose **no accessibility segments** —
  they are bare `TabGroup`s. A label-based tap silently does nothing, and the
  test then measures the *default* selection while appearing to pass. Tap them by
  coordinate (size row y≈280, difficulty y≈325, segment centres at x≈92/201/310
  for a 402pt-wide screen) and confirm by screenshot or white-cell count.
- `KakuroGame.tap()` toggles selection and the app auto-advances it, so a blind
  tap-cell-then-digit loop deselects and drops entries. Read the entries back
  from the tree (`row R, column C, <digit|empty>`) and retry until they match.
- The saved game reaches the plist through cfprefsd, which buffers. Poll for
  `kakuro.saveGame.v1` rather than reading once.

## Calibration workflow

1. Build a CLI bench (above) that loops `makeTopology` → `fill` → mutate-repair → `LogicalSolver.solve`, collecting `DifficultyRater.score` for 30+ unique+solvable candidates per size
2. Paste p33/p66 into `DifficultyRater.thresholds`
3. Re-run `GenerationTests` (band-match assertions are intentionally loose — 60% — since `generate` returns nearest-band on budget exhaustion)

## Project Configuration

- App Store name: **Just Kakuro** · Bundle ID: `de.kaikunze.kakuro` · Team: `8H42EZRCCP` · App Store Connect app id `6796701026`, SKU `7778`
  The ASC record began life as "MathMaze" on `de.kaikunze.mathmaze`; on 2026-07-31 it was renamed and repointed to `de.kaikunze.kakuro` (registered bundle id `C7X5B3UVJ4`). That was only possible because no build had been uploaded yet — **once the first build lands, the bundle ID is locked forever.** The Xcode target is still named `Kakuro`, so the product is `Kakuro.app` with display name "Just Kakuro"
- iOS 18.0+, iPhone + iPad (`TARGETED_DEVICE_FAMILY = 1,2`), portrait on iPhone, all orientations on iPad

