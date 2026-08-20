# Blockpad — write-up handoff

Source material for a project page on akabuild.dev, structured to match the
BodyLog page. Copy blocks are written to be lifted directly. Assets are listed
per section.

---

## Hero

> A sketchpad for macOS that opens over your editor on a hotkey. You draw where
> the boxes go, press copy, and paste. Your coding agent gets the layout as
> exact structure, not a paragraph and not a screenshot.

**Inline metadata:** Free and MIT licensed · Swift, SwiftUI, AppKit, macOS 14+ ·
M0 shipped, delivery in progress

**Asset:** `docs/hero.png` — the app window, transparent surround, own shadow.

---

## Why it exists

Figma and Excalidraw are good tools. They are also another tab, another context,
a lot of clicks, and an account you have to keep — and the genuinely useful tiers
cost money. None of that is wrong for design work. It is all wrong for the ninety
seconds where you just need to say where the boxes go.

Because that is usually the whole problem. You are in a repo, working with an
agent, and you need to say *"filters go in a right-side panel, tabs across the
top, reset and apply in the footer."* You type it. The agent builds something
reasonable and wrong. You correct it. Closer, still wrong. Three rounds later you
have spent real tokens, real minutes, and real attention reading implementations
you are about to throw away.

**The cost is not the message. It is the rounds.**

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

Blockpad is that workaround turned into a tool.

---

## What actually gets sent

The section that carries the argument. Show the sketch and the text side by side.

**Assets:** `docs/payload.png` (the sketch), `docs/payload.tree.txt` (the output).

Blocks are typed, so the scene graph serialises to text locally — no inference,
no model, no API call. This sketch:

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
| Tree + image | ~2,100 tokens | When proportion or feel matters. |
| Image only | ~1,981 tokens | Annotated screenshots, where the tree is meaningless. |

Roughly **17× cheaper**, and structurally *more* precise — six identical rows
collapse to `×6` with an exact count, rather than a model counting rectangles in
a JPEG and getting five.

Caveat worth keeping in the copy: image cost uses Anthropic's
`(width × height) / 750`; text cost is a character-based estimate. The point is
the order of magnitude, not the third digit.

---

## What decides arguments

The design rules, stated as decisions rather than features.

- **It persists, it does not dismiss.** UI iteration is iterative. You send a
  sketch, the agent builds it, it is 70% right, you nudge two blocks and send
  again. A launcher that clears on send would make you redraw every round. So
  the hotkey toggles rather than summons, contents survive restart, `Esc` hides
  without discarding, and clearing is explicit.
- **The tree is the default, not the image.** The opposite of what every
  screenshot tool does, and the position the whole project rests on.
- **Never press Return.** Blockpad pastes and stops. The agent might be mid-plan
  or waiting on a permission gate, and a stray prompt at the wrong moment costs
  more than the keystroke saves.
- **No model inside it.** No inference, no account, no cloud, nothing
  agent-initiated. It is an input device.
- **If a control is not in the bar, it does not exist.** Which is only honest if
  the bar stays short — hence seven dock slots, with shapes and connectors
  collapsed into flyouts.

---

## The look changed twice, on purpose

Good section for showing process, with before/after.

**Hand-drawn → crisp.** The original plan specified Excalidraw-style rough
strokes, arguing roughness signals *provisional* and stops a model reading
proportions as exact. That risk turned out to be covered elsewhere: the tree
states coordinates and counts outright, so precision never depends on the
picture. The default is now clean geometry. The rough renderer survives behind a
Crisp/Sketch toggle rather than being deleted.

**Top bar → bottom dock.** The first chrome was a top-centre island of equal
icons, which is unmistakably somebody else's signature. Moving tools to a dock
along the bottom keeps the top edge of the drawing clear — that is where you
actually look — and gives the window a silhouette of its own. The inspector
became a collapsible rail of rows: leading glyph, quiet label, control on the
trailing edge, hairline between.

---

## The mark is the operation

**Assets:** `docs/logo/logo.svg`, `logo-2048.png`, `logo-1024.png`, `logo-512.png`.

A white squircle on Apple's icon geometry — 22.37% continuous corner radius,
inset in its canvas — holding three blocks from the app's own palette: slate as
the main column, dusty red and amber stacked beside it. It is a blockout of a
layout, which is literally what the app does.

Three blocks, not four, because four turns to mush at 16pt. The drop shadow is
dropped below 64pt where it only muddies the silhouette, and the hairline border
appears only at 128pt and up, where it stops a white card dissolving into a white
page.

It is generated in Core Graphics from the palette rather than stored as a binary
asset, so changing a swatch changes the icon. The SVG is emitted from the same
ratios, so vector and raster cannot drift.

---

## Alignment guides

Grid snapping gives tidy coordinates but not tidy layouts — two boxes can both
sit on the grid and still look a step out. Dragging solves the three interesting
lines per axis (both edges and the centre) against every other block, pulls to
the nearest match, and draws a guide across the objects that share it.
Multi-selection moves as a rigid body, so its internal spacing cannot drift.

---

## Why native, not a web app

A web app cannot register a global hotkey, cannot read which application was
frontmost, and cannot post a synthetic paste event — which is the entire delivery
mechanism, not a detail of it. Tauri could do all three, but would spend a
webview against a 200ms budget.

The canvas is an `NSView` drawing through Core Graphics, hosted in SwiftUI.
AppKit because hit testing, drag handles and marquee select get miserable in pure
SwiftUI past forty blocks — and `UndoManager` comes free.

**200ms from keypress to first stroke.** That is the product.

---

## Tech stack

`Swift 6 · SwiftUI · AppKit · Core Graphics · macOS 14+ · one dependency`

No backend, no account, no inference, nothing leaves the machine.

Not App Store — the sandbox blocks synthetic events and cross-app activation, so
it ships as a signed, notarised DMG.

---

## Status

**Done**
- Floating panel, global hotkey toggle, persistent resizable canvas
- Frame, rectangle, ellipse, diamond, arrow, line, freehand, text, eraser, pan
- Stroke and fill colour, fill style, corner style, opacity, layer order
- Canvas themes, crisp/sketch renderer, component library of eight presets
- Alignment guides, grid snap, marquee select, undo/redo
- Tree serialiser with run-collapsing, three payload modes, clipboard copy
- App icon generated from the palette, MIT licensed

**Next**
- **Delivery (M1).** Capture the frontmost app before the panel takes focus, then
  paste straight into it: text everywhere, images into editors, and a
  written-to-disk path for terminals, which is what makes CLI agents work at all.
  Riskiest milestone, and the one the whole idea rests on.
- Screenshot-backed mode with redaction
- Project detection, writing sketches into `.blockpad/` beside the code they made
- Sparkle, notarisation, DMG

---

## Open questions worth naming

Honesty is part of the tone. These are unresolved.

1. **Is tree-only actually good enough as the default?** Ten sketches, tree-only
   against tree+image, into a real agent, compare the diffs. Two hours of work
   that decides the default send mode.
2. **Terminal paste.** Bracketed paste differs across Ghostty, iTerm2, Warp,
   Kitty and Terminal.app, and multi-line trees may mangle. Highest-risk unknown.
3. **Activation timing.** A fixed sleep before pasting is a magic number that
   will be flaky under load.

---

## Who built it

Ieuan King — design and build. MIT licensed, so anyone can fork it, ship it, or
take the tree format and do something better with it.

---

## Why this one matters to me

Design tools assume you are doing design. Most of the time I am not — I am trying
to be understood by something that will write the code, and the gap between what
I can see in my head and what I can type is where the time goes.

This does not make anything prettier. It makes intent cheap to transmit, so
anyone who can drag a rectangle can specify an interface well enough to have it
built. For internal tools, the ones nobody staffs a designer on, that is the
whole thing.

---

## Notes for the page

- **Hotkey in any copy must be `Ctrl+Opt+B`.** macOS holds `Ctrl+Opt+Space` for
  Input Sources by default, so it is the first thing a reader tries and the first
  thing that fails. Mention Space only as the alternative, with the fix.
- An interactive demo like BodyLog's is possible later — the renderer and tree
  serialiser are pure functions over a flat block array and would port to canvas
  or SVG in the browser.
- Repo: https://github.com/akaieuan/blockpad
