# Just Kakuro

An iPhone and iPad app that teaches you to play Kakuro, then gets out of the way.

Kakuro is a crossword with sums instead of words. Every run of white cells adds
up to its clue, and no digit repeats inside a run. That is the whole rulebook.
Getting good at it is another matter, which is what this app is for.

Website and privacy policy: <https://kaikunze.de/justkakuro/>

## What is in here

Swift 6 and SwiftUI, iOS 18 and later. No third-party dependencies.

| Path | What it holds |
|---|---|
| `Kakuro/Engine/` | Pure logic. Generator, backtracking solver, human-technique solver, difficulty rating. No SwiftUI, all `nonisolated` value types. |
| `Kakuro/Game/` | The play screen, board rendering, number pad, puzzle cache. |
| `Kakuro/Teaching/` | Lessons, the hint engine, practice drills, mastery tracking. |
| `Kakuro/Store/` | The one-time unlock. StoreKit 2 behind a protocol seam. |
| `Kakuro/Persistence/` | Settings, stats, best times and the saved game. |
| `KakuroTests/` | 108 tests. |
| `docs/ENGINEERING.md` | Architecture, invariants, and the mistakes already made once. |

## Two things worth knowing about the engine

**Every shipped puzzle is proved unique before you see it.** `generate` has a
single exit, and everything leaving it passes a check that the board has exactly
one solution and can be finished by the curriculum's own techniques. A board
that fails either test is never returned. Random Kakuro fills are almost never
unique, so uniqueness comes from a repair loop that finds where two solutions
differ and mutates that cell toward tighter sums.

**Three of the eight techniques never appear in a solver trace.** No Repeats,
Only Place and Sum Arithmetic are always reached first by a cheaper detector, so
searching for a board that exercises them cannot succeed at any size or
difficulty. Their practice drills use hand-authored boards instead. There is a
test that pins the premise, so if detector precedence ever changes, it fails and
says so.

## Building

```
xcodebuild -project Kakuro.xcodeproj -scheme Kakuro \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5' build

xcodebuild test -project Kakuro.xcodeproj -scheme Kakuro \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=18.5'
```

Pin `OS=` in the destination. An unpinned device name can match several
simulator runtimes.

## Licence

Copyright Kai Kunze. All rights reserved.
