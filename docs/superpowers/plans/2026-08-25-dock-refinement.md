# Dock Refinement Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The bottom dock reads as one considered control strip rather than a row of buttons that happen to be adjacent — even padding, one spacing rhythm, dividers that sit correctly — with the design language exactly where it is today.

**Spec:** [PLAN.md](../../../PLAN.md) §3 "Chrome". This is polish, not redesign.

---

## What is actually wrong

Read off a 2x capture of the live dock rather than from the source, because the source looks fine and the render does not:

1. **The rhythm is irregular.** Plain tools are `buttonSize` wide (34). Group buttons are 34 + 12 for the chevron. The active tool grows a label and becomes ~90 wide. Three different widths sharing one 2pt gap means the eye reads clumps, not a row.

2. **Dividers are full-height and tight.** `Divider1px` runs the full dock height and carries the same 2pt gap as everything else, so it crowds its neighbours and touches the dock's inner padding. A divider needs more air than the items it separates, and should stop short of the top and bottom edges the way `rowSeparator` already does in the inspector.

3. **The chevron reads as its own button.** Inside `ToolGroupButton` the pill and the chevron are separate hit targets with `spacing: 0` and no shared background, so the chevron looks like a detached 12pt sliver rather than part of one control.

4. **Padding is uniform where it should not be.** `.padding(Token.Space.md)` puts 6pt on all four sides. A horizontal strip of round-ish buttons needs more horizontal inset than vertical, or the first and last glyphs look pinned to the edge.

5. **No token covers any of this.** Every number above is either a literal or a general-purpose `Space` value doing a job it was not chosen for, which is exactly the drift [Tokens.swift](../../../Sources/Blockpad/UI/Tokens.swift) exists to stop.

---

## Global Constraints

- **The look does not change.** Same glass surface, same corner radius, same accent, same glyph set, same collapse-into-flyout behaviour. Someone who used it yesterday should notice it feels tidier and not be able to say what moved.
- **No behaviour changes.** Every tool, shortcut, flyout, menu and tooltip works exactly as before. The dock's public API (`buttonSize`, `showsActiveLabel`) stays.
- The dock must keep working at both sizes it is used at — the compact variant passes a smaller `buttonSize` and `showsActiveLabel: false`.
- Numbers go in `Token`, not in the view.

---

## Tasks

- [ ] **1. Dock tokens** — add a `Token.Dock` group: `itemGap`, `clusterGap` (around dividers), `insetH`, `insetV`, `dividerInset`. Nothing else in the app reads them, which is the point: a strip of icon buttons is its own context and borrowing `Space.md` for it is what produced the current spacing.

- [ ] **2. Even the padding** — replace the single `.padding(Token.Space.md)` with explicit horizontal and vertical insets so the outer glyphs sit off the edge by the same optical amount that separates them from each other.

- [ ] **3. Fix the divider** — `Divider1px` takes an inset so it stops short of the dock's top and bottom, and the layout gives it `clusterGap` either side instead of `itemGap`. This is the single biggest readability win and it is four lines.

- [ ] **4. Make the group button one control** — wrap the pill and its chevron in a shared container with one hover background spanning both, and tighten the chevron's width so it reads as an affordance on the pill rather than a neighbour. Keep the two hit targets separate; only the appearance merges.

- [ ] **5. Steady the rhythm** — give the active labelled pill a minimum width and balanced horizontal padding so the row's clumping evens out as the label changes between "Select", "Rectangle" and "Draw".

- [ ] **6. Verify by capture, not by eye on the source** — screenshot the window by id before and after at 2x, crop the dock, and compare. Check both `showsActiveLabel` states and the narrow-window variant. The dock is the one piece of chrome that is always on screen; a regression here is permanent.

---

## Non-goals

Re-laying out which tools are in the dock, changing the flyout model, moving the zoom or history islands, or introducing a new colour. If a change would be visible as a *difference* rather than as *tidier*, it is out of scope.
