# Blockpad

A macOS sketchpad that opens on a hotkey and hands drawings to whatever coding agent you're in.

Handoff plan v0.3.

---

## 1. What it is

You're in a repo working agentically. You need to say "filters go in a right-side panel, tabs across the top, reset and apply in the footer." Typing that is lossy. Figma is absurd for something you'll throw away in ninety seconds. v0 and Claude artifacts put you in a different context and hand back code you didn't ask for.

`Ctrl+Opt+Space`. A light canvas appears over your editor. Drag four boxes. `Cmd+Return`. It lands in your agent's input.

Control, not Command: Cmd belongs to app shortcuts and Opt to special characters, so Ctrl is the least contested modifier on macOS. A global hotkey shadows the frontmost app's binding everywhere, so picking a modifier your editor doesn't reach for matters more than it looks. One default collision to clear: macOS binds `Ctrl+Opt+Space` to "Select next source in Input menu" under Keyboard → Shortcuts → Input Sources. Rebindable, and the menu bar item is always a fallback.

That's the whole thing. No model inside it, no approval flows, no agent-initiated anything. It is a faster input device, and the constraint is the product.

Loop target: **six seconds, no mouse travel outside the canvas.**

---

## 2. It persists, it doesn't dismiss

Important correction to the obvious Raycast-style design.

Raycast is summon, act, vanish. Wrong model here, because UI iteration is iterative. You send a sketch, the agent builds it, it's 70% right, you nudge two blocks and send again. If the canvas cleared on send you'd redraw from scratch every round.

So:

- Hotkey **toggles** visibility, it does not summon a fresh instance
- Canvas contents persist across hide and show, and across app restart
- Window is **resizable and remembers its size and position**
- `Esc` hides, it does not discard. Clearing is explicit (`Cmd+Backspace`).
- Send does not close the window

This makes it a floating utility (closer to Stickies or Digital Color Meter) rather than a launcher overlay. That's the right register.

---

## 3. Chrome

One top bar. Five controls, nothing else.

```
[ shape ▾ ]  [ ● ● ● ● ● ]  [ stroke ▾ ]  [ frame ▾ ]        [ send ▾ ]
```

- **Shape dropdown**: Frame, Box, Text, Arrow, Callout, Pen, Redact. Keyboard shortcut shown next to each so people graduate off the dropdown.
- **Color**: five swatches inline, no picker. Ink, slate, dusty red, sage, amber.
- **Stroke**: thin / medium / thick.
- **Frame**: desktop 1440, mobile 390, custom. Sets the reference frame, optional.
- **Send**: button plus a dropdown for payload mode (§5).

No layers panel. No inspector. No sidebar. If a control isn't in that bar it doesn't exist in v1.

**Presets, later.** A second dropdown holding rough component shapes (card, dialog, sidebar, table, nav) that drag out pre-composed. Nice, not v1. Don't build a component library, build five shapes that happen to look like common patterns.

---

## 4. Look

Native Mac, light, paper. Freeform and Notes, not Raycast.

- Canvas: warm off-white around `#FAFAF8`. Paper, not white.
- Faint dot grid at 8pt, ~6% opacity
- Frames cast a soft drop shadow so they read as sheets on a desk
- Top bar: `NSVisualEffectView` light material, SF Symbols monochrome, SF Pro

**Hand-drawn strokes, Excalidraw-style.** The identity-defining choice. No rough.js for Core Graphics but the effect is around sixty lines: subdivide the path, perturb points with seeded noise, stroke twice at a slight offset.

Not decoration. Roughness signals provisional. A crisp rectangle reads as a spec and invites the model to treat proportions as exact. A sketchy one reads as intent.

Dark mode follows the system but is not the design target.

---

## 5. Payload, and the token argument

You said this saves tokens. Half right, and the correction matters for how you default the send mode.

**Images are not cheap.** Anthropic bills roughly `(w × h) / 750` tokens. A 1400x900 sketch is about **1,700 tokens**. A paragraph describing the same layout is maybe 150. Per message, the image costs more, not less.

The savings are real but they're somewhere else: **you avoid three wrong iterations.** One 1,700-token image that gets it right beats four rounds of text at 150 each plus four wrong implementations you have to read and reject. The win is in rounds, not in message size.

There's a third option that's cheap *and* precise. Because blocks are typed, you can serialize the scene graph to text locally, no inference:

```
Frame 1440x900
  Panel right w=480
    Tabs 3        "All | Active | Archived"
    List 6 rows   checkbox left
    Footer        Button ghost "Reset" | Button "Apply"
  note: panel becomes bottom drawer under 768
```

That's about **120 tokens**, roughly 14x cheaper than the image, and structurally more precise since coordinates and counts are exact rather than inferred.

What the image carries that the tree doesn't is proportion and feel. So:

| Mode | Cost | Use |
|---|---|---|
| Tree only | ~120 tok | Default. Structural changes, layout specs. |
| Tree + image | ~1,800 tok | When proportion or visual feel matters. |
| Image only | ~1,700 tok | Annotated screenshots, where the tree is meaningless. |

Making **tree-only the default** is a real position and it's the opposite of what every screenshot tool does. Worth testing rather than assuming. See §9.

---

## 6. Delivery

The hard part. Everything else is a drawing app.

On hotkey, before showing anything:

```swift
pendingTarget = NSWorkspace.shared.frontmostApplication
```

Store it first. The panel takes key focus so you can draw, so you have to already know where you came from.

| Strategy | Mechanism | Targets |
|---|---|---|
| `.pasteText` | Tree as text, synthetic Cmd+V | Everything. Simplest, works everywhere. |
| `.pasteImage` | Pasteboard image + Cmd+V | Cursor, VS Code, Zed, Claude Desktop, browsers |
| `.pastePath` | Write PNG to project dir, paste path | Terminal, iTerm2, Ghostty, Warp |
| `.manual` | Copy to clipboard, toast | Unknown apps, failures |

`.pastePath` is what makes CLI agents work at all. Terminals reject clipboard images, but every agent CLI reads a path off disk.

**Where to write.** Grab the frontmost window title via `AXUIElement`. Cursor, VS Code, Zed, and most terminals put the project or cwd in it. If you can resolve a project root, write to `.blockpad/` inside the repo and paste a relative path. Agents handle in-repo relative paths far better than absolute temp paths, and the sketch ends up versioned next to the code it produced. Fall back to a temp dir when you can't resolve one.

**Send sequence**

```
1. hide panel
2. pendingTarget.activate()
3. wait for activation (see §9.2)
4. write pasteboard
5. CGEvent post Cmd+V
6. do NOT press Return
```

Never auto-press Return. Not on principle, on practicality: the agent might be mid-plan or waiting on a permission gate, and a stray prompt at the wrong moment costs more than it saves.

Unknown apps get a one-time three-button picker on first send, remembered after.

---

## 7. Stack

- Swift 6, macOS 14+
- SwiftUI for the top bar and settings
- Canvas as an `NSView` subclass drawing through Core Graphics, hosted via `NSViewRepresentable`

AppKit for the canvas because hit testing, drag handles, and marquee select get miserable in pure SwiftUI past forty blocks. `UndoManager` comes free.

Scene model: flat array of blocks with optional parentID, semantic type, rect, text. Codable. Same array renders the canvas and serializes the tree, which is why §5 is nearly free to build.

**Why not React or Tauri.** A web app can't register a global hotkey, can't read the frontmost app, and can't post synthetic paste events, so the entire delivery mechanism is impossible in a browser. Tauri v2 *can* do all three and you already know it from Null Browser, so it's not crazy if you want to move faster in a familiar stack. But you'd pay webview cost against a 200ms budget and give up native drawing perf. Swift is the right call, this is exactly the kind of small tool it's good at.

Window: `LSUIElement`, menu bar item, no dock icon. `NSPanel` with `.nonactivatingPanel`, `.floating`, `[.canJoinAllSpaces, .fullScreenAuxiliary]`. Built at launch, reused forever, never constructed on hotkey.

**200ms from keypress to first stroke.** This is the product. Instrument it, put the number in a debug HUD.

Dependencies: `KeyboardShortcuts`, `Sparkle`. That should be the list.

No backend, no account, no inference. **Not App Store**, the sandbox blocks synthetic events and cross-app activation. Signed, notarized DMG.

---

## 8. Build order

**M0, one weekend.** Panel, hotkey toggle, resizable canvas, Frame/Box/Text, hand-drawn renderer, top bar, copy to clipboard. No delivery. Use it yourself for a week. If the loop isn't good at M0 it won't get better.

**M1.** Delivery. Frontmost capture, four strategies, six adapters, Accessibility permission flow. Riskiest milestone.

**M2.** Tree serializer, send-mode dropdown.

**M3.** Screenshot-backed mode (`Ctrl+Opt+S`, region grab as locked background layer) plus redaction. Requires Screen Recording, gate the prompt behind first use of this mode only.

**M4.** Project detection, `.blockpad/` write target, persistence, adapter learning.

**M5.** Shape presets, Sparkle, notarization, DMG.

Permissions are both deferred and neither happens at onboarding. Accessibility on first send, Screen Recording on first screenshot. A permission wall at launch is the difference between 80% activation and 30%.

---

## 9. Open questions

1. **Is tree-only actually good enough as the default?** Load-bearing for §5. Ten sketches, tree-only vs tree+image, into Claude Code, compare the diffs. Two hours of work and it decides the default send mode. If the image turns out to matter more than the math suggests, flip it.
2. **Activation timing.** A fixed sleep before pasting is a magic number and will be flaky under load. Check whether `NSWorkspace.didActivateApplicationNotification` can gate it properly.
3. **Terminal paste.** Bracketed paste differs across Ghostty, iTerm2, Warp, Kitty, Terminal.app, and multi-line trees may mangle. Highest-risk unknown in M1. Test each before fixing the tree format.
4. **Does roughness hurt model parsing?** §4 assumes the tree covers precision so the image can be loose. Probably true, unverified, falls out of the same test as question 1.

---

## 10. Later, if it works

**MCP server.** Ship one and agents pull instead of you pushing: `latest_sketch()`, `list_sketches(n)`. Sidesteps synthetic paste entirely for MCP-capable clients. Requires per-client config so it's a power-user path, not a replacement for paste. Not v1.

**Custom shape sets.** JSON-defined, pointed at a registry. Your own primitives become drawable shapes.

---

## 11. Non-goals

Not a design tool. No layers, no color picker, no Figma export, no collaboration, no cloud, no account, no LLM inside the app, no Windows until Mac is actually good.

---

Name: **Blockpad**. Runner-ups: Blockout and Scratchy (the film and animation term for the rough layout pass, which is literally the operation), Stub, Plate, Napkin.
