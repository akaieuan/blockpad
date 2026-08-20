# Blockpad

A macOS sketchpad that opens on a hotkey and hands drawings to whatever coding agent you're in.

See [PLAN.md](PLAN.md) for the full design. This repo is at **M0**.

## Build and run

```bash
./Scripts/bundle.sh && open build/Blockpad.app
```

Runs as a menu bar item with no dock icon. Two hotkeys toggle the canvas:
`Ctrl+Opt+Space` and `Ctrl+Opt+B`.

macOS ships `Ctrl+Opt+Space` bound to "Select next source in Input menu", and a system
binding wins, so on a clean machine that chord may do nothing. Either clear it in
System Settings → Keyboard → Keyboard Shortcuts → Input Sources, or use `Ctrl+Opt+B`,
which nothing else claims. The menu bar item toggles the canvas either way.

## Headless render

There is no simulator for Mac apps, so the renderer can be inspected without a screen:

```bash
swift build && .build/debug/Blockpad --render-sample ./build/sample
```

Writes `sample.png` and `sample.tree.txt` from the §5 example scene. This is also the
fixture for open question #1.

## Keys

| | |
|---|---|
| `1`–`0` | tools, left to right along the bar |
| `V` `H` `F` `R` `O` `D` `A` `L` `P` `T` `E` | select, pan, frame, rect, ellipse, diamond, arrow, line, draw, text, eraser |
| padlock | keeps a tool active; off, it reverts to select after one shape |
| drag | draw · `Shift` constrains · `Cmd` disables 8pt snap |
| double-click | edit label, or place text on empty canvas |
| `Cmd+Return` | copy payload |
| `Cmd+Z` / `Cmd+Shift+Z` | undo / redo |
| `Cmd+D` / `Cmd+A` | duplicate / select all |
| `Cmd+0` / `Cmd+9` | zoom 100% / zoom to fit |
| `Cmd+[` / `Cmd+]` | send backward / bring forward (`Shift` for all the way) |
| `Cmd+Backspace` | clear canvas (explicit — `Esc` never discards) |
| `Esc` | drop tool, then selection, then hide |
| space-drag, scroll | pan · `Ctrl`- or `Cmd`-scroll or pinch zooms |

## State of play

M0 is done, and the chrome has since been rebuilt around a crisp, Figma-style
look rather than the hand-drawn one §4 specified. Roughness now lives behind a
Crisp/Sketch toggle in the properties panel; see the note at the top of
`BlockRenderer.swift` for why the precision argument in §4 still holds without it.

Chrome is floating glass islands over a full-bleed canvas, not a bar: a tool
island, a properties rail, zoom and history, and a component library. Shapes are
rectangle, ellipse, diamond, arrow, line, freehand, text and frame, with stroke
and fill colour, fill style, corner style, opacity and layer order.

Persistence and the tree serializer landed early — the tree was needed to run
open question #1 at all.

Not built yet: delivery (M1). The Copy button puts the payload on the clipboard;
nothing is pasted into the target app. `PanelController` already captures the
frontmost app on show, which is the part of §6 that is easy to get wrong.
