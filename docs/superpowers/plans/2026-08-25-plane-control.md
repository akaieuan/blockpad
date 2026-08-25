# Plane Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A rectangle can be tilted onto a plane — so a sketch can show a screen in perspective, an isometric stack of layers, or a card at an angle — and the payload says what the tilt *means* rather than where four corners happen to be.

**Spec:** [PLAN.md](../../../PLAN.md) §5 "Payload", and §4 "Look" — this is the first feature that adds a dimension the tree has to describe.

---

## The decision this plan turns on

The question was whether a tilted plane serializes as **four corner points** or as **a rect plus a named projection**. It is worth settling first, because it decides the model, not just the wire format.

**It should be a rect plus a transform, and the transform should be affine.**

Three reasons, in order of weight:

**1. Affine is what the receiving agent can act on.** A rect with `rotate` and `skew` maps one-to-one onto a CSS `transform`. Four arbitrary corners do not: a general quadrilateral is a *projective* transform, and CSS cannot express one without a full `matrix3d` and a perspective origin. So four corners hand the agent a shape it can only approximate, while an affine transform hands it a line it can paste. That is the entire product thesis — the tree states things the agent can use, which is why colours became hex and positions became coordinates.

**2. A rect stays a rect.** Every other feature in the app assumes blocks have edges: alignment guides solve three lines per axis, the grid snaps, the export infers nesting from containment, and runs collapse to `×6` because siblings share a size. A free quad breaks all of it — there is no "left edge" of an arbitrary quadrilateral to align to. Keeping the rect and carrying the tilt beside it means snapping, alignment, resize and the run detector all keep working untouched.

**3. It is cheaper and it reads.** `Box 320x200 @40,60 iso-top` against eight coordinates that a human reading the tree cannot decode. The tree is meant to be legible to the person pasting it, not only to the model.

**The escape hatch:** dragging a corner freely produces something affine only if the opposite corners stay parallel. Free-corner dragging is therefore *not* offered in this plan — the handles set rotation and skew, and the isometric presets set both at once. If a genuine quad is ever needed, it should arrive as a separate `quad` kind that opts out of layout, rather than by loosening what a `Box` is.

**Consequence for the payload:** a tilted block emits its untilted rect plus the transform. An agent that ignores the transform still gets a correct flat layout, which is the right failure mode — the tilt is presentation, the rect is structure.

---

## Global Constraints

- Swift 6, `.swiftLanguageMode(.v5)`, macOS 14+. No new dependencies.
- **Existing scenes must open unchanged.** `transform` is optional and absent means identity, exactly as `fontSize` and `curve` did.
- The tree's existing lines must not change for untilted blocks. A tilt appends; it never rewrites.
- Hit testing must invert the transform rather than approximate it, or clicking a tilted block will be off by more the further it tilts.
- Alignment, snapping and run detection continue to operate on the **untransformed** rect. This is deliberate: you align the layout, not its projection.

---

## Model

`Sources/Blockpad/Model/Transform2D.swift` — new:

```swift
struct Transform2D: Codable, Equatable {
    var rotation: Double = 0     // degrees, clockwise
    var skewX: Double = 0        // degrees
    var skewY: Double = 0        // degrees
    var scaleY: Double = 1       // foreshortening, which is what sells a plane
}
```

Plus the presets that set all four at once — `isoTop`, `isoLeft`, `isoRight`, and `flat` — because the isometric trio is the case people actually want and nobody wants to dial in −30°/30°/0.866 by hand.

`Block` gains `var transform: Transform2D?`, `nil` meaning identity.

The affine matrix is built once, in one place, and shared by the renderer, hit testing, and the SVG/PNG export, the way `Connector` and `IconRender.faces` already are. It belongs in `BlockpadKit` so it can be tested without AppKit.

---

## Tasks

- [ ] **1. `BlockpadKit/Transform2D.swift`** — the struct, the presets, `matrix` (a `CGAffineTransform` about the rect's centre), and `invert`. Tests: identity round-trips a point; each isometric preset maps a unit square to the expected rhombus; inverse ∘ forward is the identity to 1e-9; a degenerate `scaleY: 0` does not produce NaN.

- [ ] **2. Model** — `Block.transform`, `Codable` with `decodeIfPresent`, and a test that a scene saved before this feature decodes with `transform == nil` and renders identically.

- [ ] **3. Renderer** — `BlockRenderer` concats the matrix around the existing shape drawing, so fills, strokes, corner radii, hachure and text all tilt without any per-shape work. Text tilts with its box; that is the point of a plane.

- [ ] **4. Hit testing** — `blockHit` transforms the click into the block's local space via `invert` before the existing containment test. One change, correct at any angle.

- [ ] **5. Handles** — a rotation handle above the box and a skew handle on the top edge, plus `Shift` snapping rotation to 15° (reuse `Connector.snapToAngle`). Corner handles keep resizing the untilted rect.

- [ ] **6. Inspector** — a Plane row: the four isometric presets as segments, then Rotation and Skew as `NumberControl`s with the wrapping behaviour Angle already uses.

- [ ] **7. Export** — emit `iso-top` (or `rot 12° skew -8°`) after the anchor, only when the transform is not identity. Update `docs/payload.tree.txt` and the README example. Test that an untilted scene's tree is byte-identical to before.

- [ ] **8. Verify by hand** — draw a three-layer isometric stack, confirm it reads as a plane, paste the tree into an agent and check it produces a CSS transform rather than four coordinates.

---

## Non-goals

Real 3D. There is no camera, no z-ordering by depth, no lighting. A plane is a 2D rectangle with an affine transform, and the moment that stops being enough the answer is a 3D tool, not this one.
