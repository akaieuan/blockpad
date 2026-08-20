# Blockpad

A macOS sketchpad that opens on a hotkey and hands drawings to whatever coding agent you're in.

See [PLAN.md](PLAN.md) for the full design. This repo is at **M0**.

## Build and run

```bash
./Scripts/bundle.sh && open build/Blockpad.app
```

Runs as a menu bar item with no dock icon. Toggle the canvas with `Ctrl+Opt+Space`.

macOS binds `Ctrl+Opt+Space` to "Select next source in Input menu" by default. Clear it
in System Settings → Keyboard → Keyboard Shortcuts → Input Sources, or the hotkey will
fight it. The menu bar item toggles the canvas either way.

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
| `V` / `F` / `B` / `T` | select, frame, box, text |
| `1`–`5` | ink, slate, dusty red, sage, amber |
| drag | draw · `Shift` constrains · `Cmd` disables 8pt snap |
| double-click | edit label, or place text on empty canvas |
| `Cmd+Return` | copy payload |
| `Cmd+Z` / `Cmd+Shift+Z` | undo / redo |
| `Cmd+D` / `Cmd+A` | duplicate / select all |
| `Cmd+0` / `Cmd+9` | zoom 100% / zoom to fit |
| `Cmd+Backspace` | clear canvas (explicit — `Esc` never discards) |
| `Esc` | drop tool, then selection, then hide |
| space-drag, scroll | pan · `Cmd`-scroll or pinch zooms |

## State of play

M0 is done: panel, hotkey toggle, resizable canvas, Frame/Box/Text, hand-drawn
renderer, top bar, copy to clipboard. Persistence and the tree serializer landed
early — the tree was needed to run open question #1 at all.

Not built yet: delivery (M1). The Copy button puts the payload on the clipboard;
nothing is pasted into the target app. `PanelController` already captures the
frontmost app on show, which is the part of §6 that is easy to get wrong.
