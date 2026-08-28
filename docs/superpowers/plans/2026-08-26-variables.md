# Variables Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A colour or number can be given a name once and used everywhere, and the payload hands the agent the names *and* the values — so it writes `var(--surface)` instead of `#E5E3DF` scattered through a stylesheet. With modes, one drawing carries light and dark at the same time.

**Reference:** [Figma's variables and collections](https://help.figma.com/hc/en-us/articles/15145852043927-Create-and-manage-variables-and-collections) — the source of the idea, not the spec. Most of it is deliberately not being built; see Non-goals.

**Spec:** [PLAN.md](../../../PLAN.md) §5 "Payload", §11 "Non-goals".

---

## Why this belongs here at all

Blockpad's whole argument is that the tree states things the receiving agent can act on. That argument is why colours became hex instead of `[slate]`: a palette name was a lookup the receiver could not perform.

Variables are the same argument one level up. `fill #E5E3DF` tells an agent what colour to use *this once*. `fill $surface` tells it what the colour *means* — and an agent building a real interface should be emitting a token, not pasting a literal into fourteen rules. The sketch stops describing one screen and starts describing a system, which is the difference between output you keep and output you rewrite.

**Modes are where the actual leverage is.** Without them this feature is named colours, which the palette already half-does. With them, one drawing carries light and dark simultaneously, the canvas can switch between them, and the tree emits both. That is a thing you cannot do today without drawing the screen twice.

---

## The decisions this plan turns on

**1. A bound value emits the name *and* the literal — never the name alone.**

The tree emits `fill $surface #E5E3DF`, not `fill $surface`.

An agent that knows nothing about the token table still gets a working colour, exactly as an agent that ignores a plane still gets a correct flat layout. A bare `$surface` would be a lookup the receiver cannot perform without reading the table first — which is precisely the objection that killed palette names in the first place. The literal is not redundant; it is the fallback that makes the token safe to add.

**2. Modes are a property of a collection, not of a variable.**

A collection has modes (Light, Dark), and every variable in it has one value per mode. That is Figma's model and it is right: modes only mean anything if a whole set switches together. A per-variable mode list would let half a palette be dark while the other half is light.

**3. The canvas renders one mode at a time; the payload carries all of them.**

Switching mode restyles the canvas so you can see the dark version. The tree still emits every mode's value in the token table, with the inline literal being the mode currently shown. So the drawing is always truthful about what you are looking at, and the payload is always complete.

**4. Accessible checks contrast in every mode, not just the visible one.**

This is the synthesis that makes the feature more than a convenience. The classic shipped bug is a palette that passes in light and fails in dark. Because the token table holds every mode's value, `StyleTemplate` can check them all and report *which mode* fails. Nothing else in the app can do that.

**5. No aliases in v1.**

Figma lets a variable reference another (`surface` → `grey-100`). That is how mature token systems are structured and it is genuinely useful information for an agent — but it doubles the model, needs cycle detection, and none of it reaches the payload in a form that changes what the agent writes. Deferred, deliberately, and noted here so the omission is a decision rather than an oversight.

---

## Global Constraints

- Swift 6, `.swiftLanguageMode(.v5)`, macOS 14+. No new dependencies.
- **A scene with no variables must be byte-identical in the tree to today.** This is the acceptance test for not having broken the payload.
- Existing scenes open unchanged: `variables` is an optional document field, absent meaning none.
- Unbinding restores the literal that was in force. Deleting a variable that is in use must not silently blank the blocks bound to it — they keep their last resolved value.
- A block stores a *binding*, not a resolved copy. Resolution happens at render and export time, or renaming a colour would not update anything.
- Numbers and colours only. No strings, no booleans — Blockpad has no property that would take them.

---

## Model

`Sources/BlockpadKit/Variables.swift` — pure, testable, no AppKit:

```swift
public enum VariableValue: Equatable { case colour(String), number(Double) }

public struct Variable: Identifiable, Equatable {
    public let id: UUID
    public var name: String              // "surface", "radius/card"
    public var values: [String: VariableValue]   // keyed by mode name
}

public struct VariableCollection: Identifiable, Equatable {
    public let id: UUID
    public var name: String              // "Colour", "Spacing"
    public var modes: [String]           // ["Light", "Dark"]
    public var variables: [Variable]
}
```

And the binding, on `Block`:

```swift
public struct Binding: Codable, Equatable {
    public var property: BoundProperty   // .fill, .stroke, .cornerRadius, .strokeWidth, .fontSize
    public var variableID: UUID
}
```

Resolution is one function — `resolve(_ binding:, in: collections, mode:) -> VariableValue?` — used by the renderer, the inspector and the export alike, so the three cannot disagree.

---

## Payload

The table leads, the same way a checked template does, because it changes how everything under it reads:

```
variables Colour [Light, Dark]
  $surface   #FFFFFF  #14181F
  $ink       #14181F  #F4F5F7
  $accent    #F97316  #F97316
Frame 1440x900  @0,0  "Desktop"
  Box 480x900  @960,0  fill $surface #FFFFFF  stroke $ink #14181F
```

Three properties earn their place: the name says intent, the literal keeps it usable without the table, and the table gives every mode so the agent can generate both themes from one sketch.

---

## Tasks

- [x] **1. `BlockpadKit/Variables.swift`** — the types above plus `resolve`. Tests: a variable resolves per mode; a missing mode falls back to the collection's first mode rather than returning nil; a deleted variable resolves to nil and the caller keeps its literal; duplicate names within a collection are rejected; names normalise (trimmed, no `$`, no spaces).

- [x] **2. Token emission** — `Variable.token` (`$surface`) and a `VariableCollection.treeHeader` producing the block above. Tests: a collection with one mode omits the mode list; no collections emits nothing at all.

- [x] **3. `Block.bindings`** — optional array, `Codable` with `decodeIfPresent`. Test that a pre-variables scene decodes with none and its tree is byte-identical.

- [x] **4. Store** — collections persisted with the scene, plus `activeMode`. Changing mode triggers a redraw and nothing else.

- [x] **5. Resolution in the renderer** — a bound property reads through `resolve` at draw time, falling back to the block's own literal when the variable is gone.

- [x] **6. Inspector** — a bind affordance on the rows that support it (Stroke, Fill, Radius, Weight, Text), showing the token name when bound. Plus a Variables panel to create, rename, retype and delete, and a mode switcher in the Canvas section.

- [x] **7. Export** — the header, and `$name literal` inline for bound properties. Test that an unbound scene is unchanged.

- [x] **8. Accessible across modes** — extend `StyleTemplate.violations` to take a set of mode-resolved subjects and report the failing mode in the message ("Contrast 3.1:1 in Dark, needs 4.5:1"). Tests: a pair passing in Light and failing in Dark is reported once, naming Dark.

- [x] **9. Verify by hand** — build a two-mode palette, bind a form to it, switch modes, confirm the canvas restyles and the tree carries both. Paste it and check the agent emits CSS custom properties rather than literals.

---

## Non-goals

Everything else Figma has. No aliases, no scoping rules, no per-variable property restrictions, no collection limits, no library publishing, no string or boolean variables, no variable modes on individual blocks. If this starts needing a management UI with search and filtering, it has stopped being a sketchpad's token list and become a design system tool — which §11 rules out, and which Figma already does better.
