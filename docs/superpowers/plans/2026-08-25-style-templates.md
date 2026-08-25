# Style Templates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Pick a template — Modern Minimal, Accessible, Storyboard, User Story — and the canvas adopts a coherent set of defaults, so a sketch arrives at the agent already saying what kind of artefact it is.

**Spec:** [PLAN.md](../../../PLAN.md) §4 "Look" and §5 "Payload".

---

## The decision this plan turns on

A template is tempting to build as "a bundle of default colours". That would be a skin, and a skin is not worth a feature. The four names the idea started with are not four skins — they are **two different kinds of thing**, and conflating them is the main risk here.

**Templates that change how it looks.** Modern Minimal is a set of defaults: stroke, fill, radius, weight, text size, paper. It changes the drawing's appearance and nothing else. The tree is unaffected beyond the hex values it already carries.

**Templates that change what it means.** The other three each add a *constraint or a structure* that the payload has to carry, or the template is a lie:

- **Accessible** is the only one that is checkable, and that is what makes it the most valuable of the four. It should enforce, not suggest: minimum 4.5:1 contrast between fill and stroke, minimum 44pt touch targets, minimum 16pt text. It should flag violations on the canvas as you draw. And the tree must say `template accessible` — because an agent receiving it should be told these are requirements, not a colour scheme it can improve on.
- **Storyboard** is not a style, it is a *layout convention*: a row of frames at a fixed aspect, each captioned, read left to right. The template's real job is the frame preset and the flow, not the stroke width.
- **User Story** is a structure too: a title, an actor, a set of steps. Closer to a component preset than to a theme.

**So: build the two mechanisms separately.** A `StyleTemplate` that carries defaults and optional constraints, and — for Storyboard and User Story — reuse the existing component-preset machinery, which already knows how to stamp a shaped set of blocks onto the canvas. Do not force a "row of six captioned frames" through a struct designed to hold a stroke colour.

**Consequence for the payload:** the active template goes in the tree's first line. It is the cheapest possible context — one word — and it changes how everything under it should be read. An agent told `accessible` should not offer a 3:1 grey.

---

## Global Constraints

- Swift 6, `.swiftLanguageMode(.v5)`, macOS 14+. No new dependencies.
- Templates set *defaults for new blocks*. They must never silently restyle what is already drawn — offer it as an explicit "Apply to existing" action instead.
- Existing scenes open with no template and behave exactly as now.
- Constraint violations warn; they never block drawing. This is a sketchpad.
- One word in the tree, not a block of preamble. If the template needs a paragraph to explain itself, it is not a template.

---

## Model

`Sources/BlockpadKit/StyleTemplate.swift` — pure and testable:

```swift
struct StyleTemplate {
    let id: String                 // "modern-minimal", "accessible", ...
    let name: String
    let defaults: StyleDefaults    // stroke, fill, radius, weight, fontSize, paper
    let constraints: [Constraint]  // empty for the purely visual ones
}
```

`Constraint` is where the value is:

```swift
enum Constraint {
    case minContrast(Double)       // fill vs stroke, WCAG relative luminance
    case minTapTarget(CGFloat)     // shortest side of an interactive block
    case minFontSize(CGFloat)
}
```

Contrast needs a real WCAG relative-luminance implementation — the sRGB gamma expansion, not a naive brightness average, which is wrong in exactly the mid-tones people pick. `HexColor` is the natural home and is already tested.

---

## Tasks

- [ ] **1. `BlockpadKit/StyleTemplate.swift`** — the struct, the four templates, and `violations(of:in:)` returning what a block breaks. Tests: known WCAG pairs (black on white 21:1, #767676 on white 4.54:1, #777 on white 4.48:1 → fails); a 40pt button fails the 44pt rule and a 44pt one passes; templates with no constraints return nothing.

- [ ] **2. WCAG luminance in `HexColor`** — `relativeLuminance` and `contrastRatio(_:_:)`, with the sRGB gamma expansion. Tests against the published reference values.

- [ ] **3. Store** — `activeTemplate`, persisted with the scene. Applying one sets `store.style` defaults only; existing blocks are untouched.

- [ ] **4. Inspector** — a Template row in the Canvas section, as a menu. Below it, when a template has constraints, a live count of violations with a click-to-select.

- [ ] **5. Canvas warning affordance** — a violating block gets a subtle marker, not a red box. Sketches are provisional; a wall of errors is hostile.

- [ ] **6. Storyboard and User Story as component presets** — a captioned frame row and a story scaffold, in `ComponentPreset`, which already stamps grouped blocks. These two get no `StyleTemplate` entry beyond their defaults.

- [ ] **7. Export** — emit `template accessible` on the frame line when a template with constraints is active. Purely visual templates emit nothing; their effect is already in the hex values. Test that the no-template tree is byte-identical to before.

- [ ] **8. Verify by hand** — draw a form under Accessible with a deliberately low-contrast fill, confirm it flags, paste the tree, confirm the agent treats the constraint as a requirement.

---

## Non-goals

A theme editor. Four templates, defined in code, versioned with the app. The moment templates become user-editable this stops being a sketchpad and starts being a design system tool, which [PLAN.md](../../../PLAN.md) §11 rules out.
