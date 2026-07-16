# editor-harness

Drives the **real** editor — real bridge, real `EditorDocument`, real SwiftUI
panels — from the command line, and renders the panels to PNG. Never opens a
window, never takes focus.

It exists because the editor's interesting bugs live *between* the layers, where
unit tests don't look: the snapshot decoder dropped `material:binding` entirely,
so no mesh in any real file could resolve its material — every unit test passed,
because they all hand-built their stages.

```bash
scripts/harness.sh                              # run every scenario
scripts/harness.sh Tools/EditorHarness/Scenarios/material-editing.json

Tools/EditorHarness/.build/debug/editor-harness dump Tests/Fixtures/material-shader.usda --select /Car/Body
Tools/EditorHarness/.build/debug/editor-harness shot Tests/Fixtures/material-shader.usda --select /Car/Body --tab material
```

Requires a `python3` with `usd-core` importable — the same dependency the app's
Open… has. `scripts/harness.sh` skips (exit 0) when it's missing.

## Scenarios

A scenario is JSON: open a stage, drive steps, assert, screenshot. Committed
under `Scenarios/`, so a run is reviewable and re-runnable rather than a pile of
ad-hoc flags. Paths are relative to the repo root.

```json
{ "name": "material-editing",
  "open": "Tests/Fixtures/material-shader.usda",
  "steps": [
    { "do": "select", "path": "/Car/Body" },
    { "do": "expect", "surfacePath": "/Looks/Paint/Surface" },
    { "do": "shot", "name": "1-opened", "tab": "material" },
    { "do": "material.set", "input": "roughness", "number": 0.9 },
    { "do": "expect", "materialInput": "roughness", "number": 0.9 },
    { "do": "undo" },
    { "do": "expect", "materialInput": "roughness", "number": 0.4 }
  ] }
```

| verb | operands | does |
|---|---|---|
| `select` | `path` | set the selection |
| `shot` | `name`, `tab` | render that inspector tab → `<out>/<name>.png` |
| `material.set` | `input`, + `number` \| `color` | set a PreviewSurface input (undoable) |
| `material.clear` | `input` | un-author an input (revert to default) |
| `undo` / `redo` | `count` (default 1) | drive the command stack |
| `expect` | see below | assert; a failure exits 1 |
| `dump` | — | print resolved document state |

`expect` takes one of: `materialInput` + (`number` \| `color` \| `isNull`), or
`surfacePath`. Numeric comparisons use a 1e-6 tolerance because USD stores these
inputs as 32-bit floats — a `0.4` in a `.usda` reads back as `0.4000000059604645`.

Steps default `path` to the current selection. Output goes to `.harness-out/<name>/`
with a `transcript.md` describing the run next to its screenshots.

## How it stays off your screen

Two independent guarantees, both in `Render.swift`:

1. `NSApplication.setActivationPolicy(.prohibited)` — no Dock icon, never
   front-most.
2. The `NSWindow` is borderless and never ordered front (no
   `makeKeyAndOrderFront`, no `activate`). It exists only to give AppKit a view
   hierarchy to lay out; pixels come from `cacheDisplay`.

**Don't switch to SwiftUI's `ImageRenderer`.** It can't rasterise AppKit-backed
controls — the segmented `Picker`, `ColorPicker`, and `Slider` come out as a
yellow "unsupported" placeholder with the content dropped. The offscreen window
renders them for real.

## Extending

Add a verb: a `case` in `Driver.perform` plus its operands on `Scenario.Step`.
Add an assertion: a branch in `Driver.expect`. Keep the vocabulary small — it's
a harness, not a scripting language; `ScriptingKit` is where user-facing
automation belongs.

Driving the document (not synthetic clicks) is deliberate: an `EditorDocument`
mutation is exactly what an inspector click produces — the controls are thin
bindings over these methods — and it needs no window, focus, or accessibility
permissions. Screenshots cover what the clicks would *look* like.
