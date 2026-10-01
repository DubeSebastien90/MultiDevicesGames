# Archive — do not read unless asked

**This folder is not part of the project.** Do not read it, index it, or take
it into account when working on this repository, unless the user points you at
something in here explicitly and by name.

Nothing in here is compiled, tested, or shipped. It is excluded from analysis in
`analysis_options.yaml` and referenced from nowhere in `lib/`. The code will not
compile as-is: its imports still point at `../../sdk/`, which is no longer where
it sits.

It is kept because deleting work is different from retiring it — these games
were finished and played — but it is history, not context. Reading it to
understand how the platform works will teach you things that have since changed.

## What is in here

| | why it was retired |
| --- | --- |
| `games/slingshot/` | the first game the platform ever ran |
| `games/ball_bin/` | the only game that laid phones out in a column |
| `games/flood_closing/` | the shrinking-field variant of Flood, with its design notes |
| `games/random_path/` | a `Layouts.path` board with no game on it — a demo of the arrangement and its connector stripes, which Pitch Cars now plays on for real |
| `games/reaction/` | the tap-the-lit-dot reflex game |
| `games/chronometer/` | the stop-the-clock estimation game |
| `games/test_interruption/` | a debug-only dev tool for exercising NameDrop interruption, never a real game |

Alongside them sit `_removed_*.dart.txt` files: tests lifted out of the live
suite when these games went. They are kept as text rather than as Dart so that
nothing in here can be compiled or run by accident.

## Bringing one back

1. Move its folder to `lib/games/`.
2. Add one import and one entry to `lib/sdk/catalog.dart`.
3. Fix its imports — `../../sdk/…` is right again once it is under `lib/games/`.

`ball_bin` is the one with a wrinkle: it was the only user of
`Layouts.column`, and the NameDrop optimiser's tests were written against it.
Those tests now use a fixture inside `test/` instead, so the layout is still
covered and the game is not needed to prove it.
