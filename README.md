<div align="center">
<img src="docs/icon.png" width="128" alt="Blockpad">

# Blockpad

**A macOS sketchpad that opens on a hotkey and hands drawings to whatever coding agent you're in.**

[![Licence: MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](LICENSE)
![Platform: macOS 14+](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey.svg)
![Swift 6](https://img.shields.io/badge/swift-6-orange.svg)

<img src="docs/hero.png" width="880" alt="Blockpad: a floating canvas with a layout sketched on it, an inspector rail, and a tool dock">

</div>

---

## Why this exists

Figma and Excalidraw are good tools. They are also another tab, another context,
a lot of clicks, and an account you have to keep — and the genuinely useful tiers
cost money. None of that is wrong for design work. It is all wrong for the ninety
seconds where you just need to say *where the boxes go*.

Because that is usually the whole problem. You are in a repo, working with an
agent, and you need to say *"filters go in a right-side panel, tabs across the
top, reset and apply in the footer."* You type it. The agent builds something
reasonable and wrong. You correct it. Closer, still wrong. Three rounds later you
have spent real tokens, real minutes, and real attention reading implementations
you are about to throw away.

The cost is not the message. It is the **rounds**.

Blockpad is one hotkey and one canvas. `Ctrl+Opt+B`, drag four boxes,
`Cmd+Return`, paste. No model inside it, no account, no subscription, nothing
agent-initiated, and it never leaves your machine. It is a faster input device
for one specific moment, and the constraint is the product.

Two things follow, and they are the point:

**It reduces the cost of being understood.** The sketch becomes an exact scene
tree *locally*, with no inference — coordinates, counts and nesting are stated
rather than guessed from a picture. Numbers below.

**It makes design legible to people who are not designers.** Anyone who can drag
a rectangle can specify an interface well enough for an agent to build it. For
internal tools — the ones nobody staffs a designer on — that is most of the
value.

Loop target: **six seconds, no mouse travel outside the canvas.**

---

## Where this came from

I ran design at a startup, and spent most of that stretch building with agentic
tools — writing code to produce design rather than the other way round.

What I kept noticing was my own workaround. Any time I needed an agent to
actually understand a layout, I would sketch a rough wireframe and screenshot it.
Not because the screenshot was good. Because it carried my intent in a way a
paragraph never did. It was the fastest way to point at what I meant, so I did it
constantly, in whatever tool happened to be open.

The screenshot was always the wrong artifact, though. It hands over a *picture*
of a structure and asks the model to work backwards into the structure again —
which it sometimes gets right and sometimes doesn't, and either way you pay for
the guess. What was in my head was never pixels. It was "panel on the right, six
rows, two buttons in the footer."

Blockpad is that workaround turned into a tool. Same rough wireframe, same ninety
seconds — except it hands over the structure directly instead of a photograph of
it, and it opens on a keystroke without taking me out of the repo I am already
in.

---

## What it sends

Blocks are typed, so the scene graph serializes to text locally. No inference,
no model, no API call.

<img src="docs/payload.png" width="640" alt="A sketch of a filters panel">

The sketch above becomes this:

```
Frame 1440x900  "Desktop"
  Box 480x900  @right-full-height  [slate]
    Box 136x40  @left-top  "All"
    Box 136x40  @top  "Active"
    Box 136x40  @top  "Archived"
    Box 424x64  ×6  @left
      Box 24x24  @left  [sage]
    Box 200x56  @left-bottom  "Reset"  [slate]
    Box 200x56  @bottom  "Apply"  [dusty red]
  Text  @left-top  "main content unchanged"  [slate]
  Text  @left  "panel becomes bottom drawer under 768"  [amber]
```

Measured on that exact scene:

| Mode | Cost | Use |
|---|---|---|
| **Tree only** | **~117 tokens** | Default. Structural changes, layout specs. |
| Tree + image | ~2,100 tokens | When proportion or visual feel matters. |
| Image only | ~1,981 tokens | Annotated screenshots, where the tree is meaningless. |

Roughly **17× cheaper**, and structurally *more* precise — six identical rows
collapse to `×6` with an exact count, rather than a model counting rectangles in
a JPEG and getting five.

<sub>Image cost uses Anthropic's `(width × height) / 750`. Text cost is a
character-based estimate; exact tokenization varies. The point is the order of
magnitude, not the third digit.</sub>

Being honest about the other half: **an image is not automatically the expensive
choice.** One 2,000-token picture that lands the layout first time beats four
rounds of prose plus four implementations you have to read and reject. The tree
is the default because it is cheap *and* precise, but the mode switcher is right
next to the copy button for the times feel matters more than structure.

---

## Using it

Runs as a menu bar item with no dock icon. Two hotkeys toggle the canvas:
`Ctrl+Opt+B` and `Ctrl+Opt+Space`.

> **Heads up on `Ctrl+Opt+Space`.** macOS ships that chord bound to "Select next
> source in Input menu", and a system binding beats an app's. On a clean machine
> it will do nothing. Either use `Ctrl+Opt+B`, which nothing else claims, or
> clear the system one in System Settings → Keyboard → Keyboard Shortcuts →
> Input Sources.

The window **persists, it does not dismiss.** UI iteration is iterative: you
send a sketch, the agent builds it, it is 70% right, you nudge two blocks and
send again. If the canvas cleared on send you would redraw every round. So the
hotkey toggles rather than summons, contents survive hide/show and restart, the
window remembers its size and position, `Esc` hides without discarding, and
clearing is explicit.

### Tools

| | |
|---|---|
| `1`–`0` | tools, left to right along the dock |
| `V` `H` `F` `R` `O` `D` `A` `L` `P` `T` `E` | select, pan, frame, rect, ellipse, diamond, arrow, line, draw, text, eraser |
| padlock | keeps a tool active; off, it reverts to select after one shape |

Shapes and connectors each collapse into one dock slot holding whichever member
you used last, with the rest on a flyout.

### Canvas

| | |
|---|---|
| `Cmd+Return` | copy payload |
| `Cmd+Z` / `Shift+Cmd+Z` | undo / redo |
| `Cmd+D` | duplicate · `Cmd+A` select all |
| `Cmd+[` / `Cmd+]` | send backward / bring forward (`Shift` for all the way) |
| `Cmd+0` / `Cmd+9` | zoom 100% / zoom to fit |
| `Cmd+Backspace` | clear canvas |
| double-click | edit text, or start a text block on empty canvas |
| space-drag, scroll | pan · `Ctrl`- or `Cmd`-scroll or pinch zooms |
| drag with guides on | edges and centres snap to nearby blocks |

**Alignment guides** are worth calling out. Grid snapping gives tidy coordinates
but not tidy layouts — two boxes can both sit on the grid and still look a step
out. Dragging solves the three interesting lines per axis against every other
block, pulls to the nearest match, and draws a guide across the objects that
share it. Multi-selection moves as a rigid body so its internal spacing cannot
drift.

---

## Building

```bash
./Scripts/bundle.sh release
open build/Blockpad.app
```

Requires Swift 6 and macOS 14+. Dependencies are `KeyboardShortcuts` and
nothing else yet.

> Launching the bundle from inside `~/Desktop`, `~/Documents`, or `~/Downloads`
> makes macOS prompt for folder access. Blockpad only writes to
> `~/Library/Application Support/Blockpad`, so "Don't Allow" is the right answer
> — or move the `.app` somewhere neutral.

Other entry points:

```bash
./Scripts/icon.sh                              # regenerate the icon from code
.build/debug/Blockpad --render-sample ./out    # render the example scene + tree
.build/debug/Blockpad --seed-demo              # load the example into the app
```

The icon is drawn in Core Graphics rather than stored as an asset, so it cannot
drift from the palette.

---

## State of play

**M0 is done**, and then some. Panel, hotkey toggle, resizable persistent
canvas, the full shape set, the tree serializer, and clipboard payload modes all
work. Persistence and the serializer landed early because the tree was needed to
test the central assumption at all.

The look departed from the original plan twice, deliberately:

- **Crisp, not hand-drawn.** The plan argued roughness signals *provisional* and
  stops a model reading proportions as exact. That risk turned out to be covered
  elsewhere — the tree states coordinates and counts outright — so the default is
  clean Figma-style geometry. The sketch renderer is one toggle away.
- **A dock, not a top bar.** The top edge of a drawing is where you look. Tools
  live along the bottom, canvas settings sit behind one menu, and the inspector
  is a collapsible rail of rows.

**Next up is M1: delivery.** Today Blockpad copies to the clipboard and you
paste. M1 captures the frontmost app before the panel takes focus and pastes
into it directly — text everywhere, images into editors, and a written-to-disk
path for terminals, which is what makes CLI agents work at all. It is the
riskiest milestone and the one the whole idea rests on.

See [PLAN.md](PLAN.md) for the full design, the open questions, and the
reasoning behind each decision.

---

## Licence

MIT. Fork it, ship it, sell it, take the tree format and build something better
with it — no permission needed and no attribution beyond keeping the notice. See
[LICENSE](LICENSE).

---

## Non-goals

Not a design tool. No layers panel, no colour picker, no Figma export, no
collaboration, no cloud, no account, no LLM inside the app, and no Windows until
the Mac version is actually good.

---

<sub>Built by <a href="https://ubik.studio">Ubik Studio</a>.</sub>
