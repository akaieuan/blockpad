import AppKit
import BlockpadKit
import Combine

/// AppKit rather than SwiftUI because hit testing, drag handles and marquee
/// select get miserable in pure SwiftUI past forty blocks (§7). UndoManager
/// comes free.
final class CanvasView: NSView {

    let store: SketchStore
    var onSend: (() -> Void)?

    private var cancellables = Set<AnyCancellable>()
    private var editor: NSTextField?
    private var editingBlockID: UUID?
    private var drag: DragState = .none
    private var isSpaceHeld = false
    private var guides: [AlignmentGuide] = []

    /// What the floating chrome covers. Fitting to the raw bounds centres the
    /// drawing behind the inspector and the dock, which looks like the button
    /// is off rather than like the chrome is in the way.
    var chromeInsets = NSEdgeInsets(top: 56, left: 24, bottom: 68, right: 24)

    private let gridStep: CGFloat = 8
    private let handleSize: CGFloat = 8
    private let minZoom: CGFloat = 0.1
    private let maxZoom: CGFloat = 8

    init(store: SketchStore) {
        self.store = store
        super.init(frame: .zero)
        wantsLayer = true

        store.$blocks.sink { [weak self] _ in self?.needsDisplay = true }.store(in: &cancellables)
        store.$selection.sink { [weak self] _ in self?.needsDisplay = true }.store(in: &cancellables)
        store.$theme.sink { [weak self] _ in self?.needsDisplay = true }.store(in: &cancellables)
        store.$sketchy.sink { [weak self] _ in self?.needsDisplay = true }.store(in: &cancellables)
        // Retinting the whole canvas is what a mode switch *is*, so both the
        // values and the mode showing them have to reach the drawing.
        store.$collections.sink { [weak self] _ in self?.needsDisplay = true }.store(in: &cancellables)
        store.$mode.sink { [weak self] _ in self?.needsDisplay = true }.store(in: &cancellables)
        store.$paperVariableID.sink { [weak self] _ in self?.needsDisplay = true }.store(in: &cancellables)
        store.$tool.sink { [weak self] _ in
            guard let self else { return }
            self.needsDisplay = true
            self.window?.invalidateCursorRects(for: self)
        }.store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Transform

    private func toDoc(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - store.pan.x) / store.zoom, y: (p.y - store.pan.y) / store.zoom)
    }

    private func toView(_ p: CGPoint) -> CGPoint {
        CGPoint(x: p.x * store.zoom + store.pan.x, y: p.y * store.zoom + store.pan.y)
    }

    private func toView(_ r: CGRect) -> CGRect {
        CGRect(origin: toView(r.origin),
               size: CGSize(width: r.width * store.zoom, height: r.height * store.zoom))
    }

    private var visibleDocRect: CGRect {
        CGRect(origin: toDoc(bounds.origin),
               size: CGSize(width: bounds.width / store.zoom, height: bounds.height / store.zoom))
    }

    /// Grid-snaps the *result* of a move rather than the delta, so dragging a
    /// block that started off-grid lands it on the grid.
    private func snapDelta(from origin: CGFloat, delta: CGFloat) -> CGFloat {
        (((origin + delta) / gridStep).rounded() * gridStep) - origin
    }

    private func snap(_ p: CGPoint, disabled: Bool) -> CGPoint {
        guard !disabled else { return p }
        return CGPoint(x: (p.x / gridStep).rounded() * gridStep,
                       y: (p.y / gridStep).rounded() * gridStep)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        ctx.saveGState()
        ctx.translateBy(x: store.pan.x, y: store.pan.y)
        ctx.scaleBy(x: store.zoom, y: store.zoom)

        let options = store.renderOptions
        BlockRenderer.drawBackground(in: ctx, visibleDocRect: visibleDocRect,
                                     zoom: store.zoom, theme: options.theme)
        for block in store.sorted where block.id != editingBlockID {
            BlockRenderer.draw(block, in: ctx, zoom: store.zoom, options: options)
        }
        if case .creating(let block) = drag {
            BlockRenderer.draw(block, in: ctx, zoom: store.zoom, options: options)
        }
        ctx.restoreGState()

        drawRuleWarnings(in: ctx)
        drawSelectionChrome(in: ctx)
    }

    /// Selection UI is drawn in view space so its weight stays constant at any zoom.
    /// A block breaking the active template's rules gets a small marker at its
    /// top-left corner — not a red outline. A sketch is provisional by
    /// definition, and a wall of errors over someone's rough layout is hostile.
    private func drawRuleWarnings(in ctx: CGContext) {
        let flagged = store.violations
        guard !flagged.isEmpty else { return }
        let byID = Dictionary(grouping: flagged, by: \.blockID)

        ctx.saveGState()
        for block in store.blocks where byID[block.id] != nil {
            let r = toView(block.bounds)
            let dot = CGRect(x: r.minX - 3, y: r.minY - 3, width: 7, height: 7)
            ctx.setFillColor(Palette.warning.cgColor)
            ctx.fillEllipse(in: dot)
        }
        ctx.restoreGState()
    }

    private func drawSelectionChrome(in ctx: CGContext) {
        let selected = store.selectedBlocks
        ctx.saveGState()
        ctx.setStrokeColor(Palette.selection.cgColor)
        ctx.setLineWidth(1.5)

        for block in selected {
            if block.isTilted, !block.kind.isLinear, block.kind != .pen {
                // Trace the plane itself. A rectangle drawn round a tilted block
                // says nothing about where its edges actually are.
                let corners = block.plane.corners(of: block.rect.standardized).map(toView)
                let path = CGMutablePath()
                path.move(to: corners[0])
                for point in corners.dropFirst() { path.addLine(to: point) }
                path.closeSubpath()
                ctx.addPath(path)
            } else {
                let r = toView(block.bounds).insetBy(dx: -4, dy: -4)
                ctx.addPath(CGPath(roundedRect: r, cornerWidth: 4, cornerHeight: 4, transform: nil))
            }
            ctx.strokePath()
        }

        if selected.count == 1, let only = selected.first {
            for handle in handles(for: only) {
                let h = handleRect(handle, for: only)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.setStrokeColor(Palette.selection.cgColor)
                ctx.setLineWidth(1.5)
                // The bow handle is round, so it does not read as a corner you
                // could drag to resize.
                let path = (handle == .curve || handle == .rotate)
                    ? CGPath(ellipseIn: h.insetBy(dx: -0.5, dy: -0.5), transform: nil)
                    : CGPath(roundedRect: h, cornerWidth: 2, cornerHeight: 2, transform: nil)
                ctx.addPath(path); ctx.fillPath()
                ctx.addPath(path); ctx.strokePath()
            }
        }
        ctx.restoreGState()

        if !guides.isEmpty {
            ctx.saveGState()
            ctx.setStrokeColor(Palette.guide.cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [4, 3])
            for guide in guides {
                let a: CGPoint, b: CGPoint
                if guide.isVertical {
                    a = toView(CGPoint(x: guide.position, y: guide.start))
                    b = toView(CGPoint(x: guide.position, y: guide.end))
                } else {
                    a = toView(CGPoint(x: guide.start, y: guide.position))
                    b = toView(CGPoint(x: guide.end, y: guide.position))
                }
                // Overshoot a little so the line reads as a guide, not an edge.
                let pad: CGFloat = 12
                let from = guide.isVertical ? CGPoint(x: a.x, y: a.y - pad) : CGPoint(x: a.x - pad, y: a.y)
                let to = guide.isVertical ? CGPoint(x: b.x, y: b.y + pad) : CGPoint(x: b.x + pad, y: b.y)
                ctx.move(to: from)
                ctx.addLine(to: to)
            }
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.restoreGState()
        }

        if case .marquee(let start, let current) = drag {
            let r = CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                           width: abs(current.x - start.x), height: abs(current.y - start.y))
            ctx.saveGState()
            ctx.setFillColor(Palette.selection.withAlphaComponent(0.10).cgColor)
            ctx.setStrokeColor(Palette.selection.withAlphaComponent(0.75).cgColor)
            ctx.setLineWidth(1)
            ctx.fill(r); ctx.stroke(r)
            ctx.restoreGState()
        }
    }

    /// Pulls `point` onto the nearest 15° spoke around `anchor`, preserving its
    /// distance. Shared by drawing a connector and by dragging one's endpoint,
    /// so the two behave the same.
    private func snapToAngle(_ point: CGPoint, around anchor: CGPoint) -> CGPoint {
        let angle = atan2(point.y - anchor.y, point.x - anchor.x)
        let step = CGFloat.pi / 12
        let snapped = (angle / step).rounded() * step
        let length = hypot(point.x - anchor.x, point.y - anchor.y)
        return CGPoint(x: anchor.x + cos(snapped) * length,
                       y: anchor.y + sin(snapped) * length)
    }

    private func handles(for block: Block) -> [Handle] {
        if block.kind.isLinear { return [.topLeft, .bottomRight, .curve] }
        // Text scales rather than stretches, so it only needs the corners —
        // an edge handle would imply a reflow that a single line does not do.
        if block.kind == .text { return [.topLeft, .topRight, .bottomLeft, .bottomRight] }
        if block.kind == .pen { return [] }
        // Corners resize the untilted rect; the rotate handle spins it. Frames
        // stay square — a tilted reference frame is a contradiction.
        return block.kind == .frame
            ? Handle.allCases.filter { $0 != .curve && $0 != .rotate }
            : Handle.allCases.filter { $0 != .curve }
    }

    private func handleRect(_ handle: Handle, for block: Block) -> CGRect {
        let p: CGPoint
        if block.kind.isLinear {
            let (start, end) = block.endpoints
            switch handle {
            case .topLeft:     p = toView(start)
            case .curve:       p = toView(block.curveApex)
            default:           p = toView(end)
            }
        } else if handle == .rotate {
            // Rides above the middle of the block's own top edge, so it stays
            // where the shape is rather than where its bounding box is.
            let r = block.rect.standardized
            let corners = block.plane.corners(of: r)
            let mid = CGPoint(x: (corners[0].x + corners[1].x) / 2,
                              y: (corners[0].y + corners[1].y) / 2)
            let inward = CGPoint(x: r.midX - mid.x, y: r.midY - mid.y)
            let span = max(1, hypot(inward.x, inward.y))
            let lift = 18 / store.zoom
            p = toView(CGPoint(x: mid.x - inward.x / span * lift,
                               y: mid.y - inward.y / span * lift))
        } else {
            p = handle.point(in: toView(block.bounds).insetBy(dx: -4, dy: -4))
        }
        return CGRect(x: p.x - handleSize / 2, y: p.y - handleSize / 2,
                      width: handleSize, height: handleSize)
    }

    // MARK: - Hit testing

    private func blockHit(at docPoint: CGPoint) -> Block? {
        for block in store.sorted.reversed() {
            switch block.kind {
            case .frame:
                // Frames are grabbed by their edge or their label, not their body,
                // or they swallow every click inside the sheet.
                let r = block.bounds
                let outer = r.insetBy(dx: -8, dy: -8)
                let inner = r.insetBy(dx: 8, dy: 8)
                let label = CGRect(x: r.minX, y: r.minY - 24, width: max(70, r.width * 0.4), height: 24)
                if (outer.contains(docPoint) && !inner.contains(docPoint)) || label.contains(docPoint) {
                    return block
                }
            case .arrow, .line:
                let tolerance = max(8, CGFloat(block.strokeWidth) * 3) / store.zoom
                let (start, end) = block.endpoints
                if block.curve == 0 {
                    if distanceToSegment(docPoint, start, end) < tolerance { return block }
                } else {
                    // Flatten the bow and test each chunk; a curved arrow that
                    // only responds along its chord is maddening to grab.
                    let control = block.curveControl
                    var previous = start
                    for step in 1...12 {
                        let t = CGFloat(step) / 12
                        let u = 1 - t
                        let point = CGPoint(
                            x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
                            y: u * u * start.y + 2 * u * t * control.y + t * t * end.y)
                        if distanceToSegment(docPoint, previous, point) < tolerance { return block }
                        previous = point
                    }
                }
            default:
                // Tilted blocks are tested in their own space, so a click lands
                // correctly however far the plane leans.
                if block.isTilted {
                    if block.plane.contains(docPoint, in: block.rect.standardized, slop: 4) {
                        return block
                    }
                } else if block.bounds.insetBy(dx: -4, dy: -4).contains(docPoint) {
                    return block
                }
            }
        }
        return nil
    }

    private func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let lengthSq = dx * dx + dy * dy
        guard lengthSq > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / lengthSq))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    private func handleHit(at viewPoint: CGPoint) -> (UUID, Handle)? {
        guard store.selection.count == 1, let id = store.selection.first,
              let block = store.block(id) else { return nil }
        for handle in handles(for: block)
        where handleRect(handle, for: block).insetBy(dx: -3, dy: -3).contains(viewPoint) {
            return (id, handle)
        }
        return nil
    }

    // MARK: - Mouse

    override func mouseDown(with event: NSEvent) {
        commitEditor()
        window?.makeFirstResponder(self)

        let viewPoint = convert(event.locationInWindow, from: nil)
        let docPoint = toDoc(viewPoint)
        let noSnap = event.modifierFlags.contains(.command)

        if event.clickCount == 2, !store.tool.isDrawing {
            handleDoubleClick(at: docPoint)
            return
        }

        if store.tool == .hand || isSpaceHeld {
            drag = .panning(start: viewPoint, originalPan: store.pan)
            return
        }

        if store.tool == .eraser {
            drag = .erasing(snapshot: store.blocks)
            eraseHit(at: docPoint)
            return
        }

        if let kind = store.tool.kind {
            beginCreating(kind: kind, at: kind.isLinear || kind == .pen ? docPoint : snap(docPoint, disabled: noSnap))
            return
        }

        if let (id, handle) = handleHit(at: viewPoint), let block = store.block(id) {
            drag = .resizing(id: id, handle: handle, original: block.rect, snapshot: store.blocks)
            return
        }

        if let hit = blockHit(at: docPoint) {
            // Clicking one member of a group takes the whole group — that is
            // what makes grouping mean anything rather than just a label.
            let mates = groupMates(of: hit)
            if event.modifierFlags.contains(.shift) {
                if store.selection.contains(hit.id) { store.selection.subtract(mates) }
                else { store.selection.formUnion(mates) }
            } else if !store.selection.contains(hit.id) {
                store.selection = mates
            }
            drag = .moving(origin: docPoint, snapshot: store.blocks)
        } else {
            if !event.modifierFlags.contains(.shift) { store.selection = [] }
            drag = .marquee(start: viewPoint, current: viewPoint)
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let viewPoint = convert(event.locationInWindow, from: nil)
        let docPoint = toDoc(viewPoint)
        let noSnap = event.modifierFlags.contains(.command)
        let constrain = event.modifierFlags.contains(.shift)

        switch drag {
        case .creating(var block):
            if block.kind == .pen {
                block.points.append(docPoint)
                block.rect = block.bounds
            } else {
                let start = block.rect.origin
                var end = block.kind.isLinear ? docPoint : snap(docPoint, disabled: noSnap)
                if constrain {
                    if block.kind.isLinear {
                        end = snapToAngle(end, around: start)
                    } else {
                        let side = max(abs(end.x - start.x), abs(end.y - start.y))
                        end = CGPoint(x: start.x + side * (end.x < start.x ? -1 : 1),
                                      y: start.y + side * (end.y < start.y ? -1 : 1))
                    }
                }
                var rect = CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y)
                if store.snapping, !noSnap, !block.kind.isLinear {
                    let others = store.blocks.filter { $0.kind != .frame }.map(\.bounds)
                    let result = Alignment.solve(moving: rect.standardized, others: others,
                                                 tolerance: 7 / store.zoom)
                    // Only the dragged corner moves; the anchor stays put.
                    if let adjust = result.dx { rect.size.width += adjust }
                    if let adjust = result.dy { rect.size.height += adjust }
                    guides = result.guides
                } else {
                    guides = []
                }
                block.rect = rect
            }
            drag = .creating(block)

        case .moving(let origin, let snapshot):
            var dx = docPoint.x - origin.x
            var dy = docPoint.y - origin.y
            if constrain { if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 } }

            // The whole selection moves as one rigid body, so solve the offset
            // once against its union rather than snapping each block separately
            // — otherwise a multi-select quietly changes its own spacing.
            let baseUnion = snapshot.filter { store.selection.contains($0.id) }
                .map(\.bounds).reduce(CGRect.null) { $0.union($1) }

            var alignedX = false
            var alignedY = false
            if store.snapping, !noSnap, !baseUnion.isNull {
                let others = snapshot.filter { !store.selection.contains($0.id) && $0.kind != .frame }
                    .map(\.bounds)
                let result = Alignment.solve(moving: baseUnion.offsetBy(dx: dx, dy: dy),
                                             others: others,
                                             tolerance: 7 / store.zoom)
                if let adjust = result.dx { dx += adjust; alignedX = true }
                if let adjust = result.dy { dy += adjust; alignedY = true }
                guides = result.guides
            } else {
                guides = []
            }

            // Grid snap only where alignment did not already decide the axis.
            if !noSnap, !baseUnion.isNull {
                if !alignedX { dx = snapDelta(from: baseUnion.minX, delta: dx) }
                if !alignedY { dy = snapDelta(from: baseUnion.minY, delta: dy) }
            }

            var updated = snapshot
            for i in updated.indices where store.selection.contains(updated[i].id) {
                updated[i].rect = snapshot[i].rect.translated(dx: dx, dy: dy)
                updated[i].points = snapshot[i].points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
            }
            store.blocks = updated

        case .resizing(let id, let handle, let original, let snapshot):
            guard let index = store.blocks.firstIndex(where: { $0.id == id }) else { return }
            var blocks = snapshot
            let block = snapshot[index]
            if block.kind.isLinear {
                let origin = original.origin
                let far = CGPoint(x: origin.x + original.size.width,
                                  y: origin.y + original.size.height)
                if handle == .curve {
                    // Bow is the signed perpendicular distance from the chord,
                    // normalised by its length so the shape survives a resize.
                    let dx = far.x - origin.x, dy = far.y - origin.y
                    let length = hypot(dx, dy)
                    if length > 0.001 {
                        let mid = CGPoint(x: (origin.x + far.x) / 2, y: (origin.y + far.y) / 2)
                        let nx = -dy / length, ny = dx / length
                        let reach = (docPoint.x - mid.x) * nx + (docPoint.y - mid.y) * ny
                        blocks[index].curve = Double(max(-1.5, min(1.5, reach / length)))
                    }
                } else {
                    var moving = docPoint
                    if constrain {
                        let anchor = handle == .topLeft ? far : origin
                        moving = snapToAngle(moving, around: anchor)
                    }
                    blocks[index].rect = handle == .topLeft
                        ? CGRect(x: moving.x, y: moving.y,
                                 width: far.x - moving.x, height: far.y - moving.y)
                        : CGRect(x: origin.x, y: origin.y,
                                 width: moving.x - origin.x, height: moving.y - origin.y)
                }
            } else if handle == .rotate {
                let r = original.standardized
                let centre = CGPoint(x: r.midX, y: r.midY)
                // Straight up from the centre is zero, so the handle sits where
                // the cursor does rather than 90° away from it.
                var degrees = Double(atan2(docPoint.y - centre.y, docPoint.x - centre.x)
                                     * 180 / .pi) + 90
                if constrain { degrees = (degrees / 15).rounded() * 15 }
                var plane = block.plane
                plane.rotation = degrees.truncatingRemainder(dividingBy: 360)
                blocks[index].transform = plane.isIdentity ? nil : plane
            } else if block.kind == .text {
                // Dragging a corner scales the type. Stretching the box would do
                // nothing visible, which is why text had no handles at all.
                let box = original.standardized
                let proposed = handle.resize(box, to: docPoint).standardized
                let ratio = box.width > 1 ? proposed.width / box.width : 1
                let base = BlockRenderer.fontSize(for: block)
                let scaled = min(max((Double(base * ratio)).rounded(),
                                     BlockRenderer.fontSizeRange.lowerBound),
                                 BlockRenderer.fontSizeRange.upperBound)
                blocks[index].fontSize = scaled
                let size = BlockRenderer.measure(block.text, size: CGFloat(scaled))
                // Anchor the corner opposite the one being dragged, so the block
                // grows away from the hand rather than jumping under it.
                let anchor = handle.anchor(in: box)
                blocks[index].rect = CGRect(
                    x: anchor.x == box.maxX ? anchor.x - size.width : anchor.x,
                    y: anchor.y == box.maxY ? anchor.y - size.height : anchor.y,
                    width: size.width, height: size.height)
            } else {
                blocks[index].rect = handle.resize(original.standardized,
                                                   to: snap(docPoint, disabled: noSnap))
            }
            store.blocks = blocks

        case .marquee(let start, _):
            drag = .marquee(start: start, current: viewPoint)
            let r = CGRect(x: min(start.x, viewPoint.x), y: min(start.y, viewPoint.y),
                           width: abs(viewPoint.x - start.x), height: abs(viewPoint.y - start.y))
            let docRect = CGRect(origin: toDoc(r.origin),
                                 size: CGSize(width: r.width / store.zoom, height: r.height / store.zoom))
            let caught = store.blocks.filter { docRect.intersects($0.bounds) }
            store.selection = caught.reduce(into: Set<UUID>()) { $0.formUnion(groupMates(of: $1)) }

        case .erasing:
            eraseHit(at: docPoint)

        case .panning(let start, let originalPan):
            store.pan = CGPoint(x: originalPan.x + (viewPoint.x - start.x),
                                y: originalPan.y + (viewPoint.y - start.y))

        case .none:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch drag {
        case .creating(var block):
            let r = block.rect.standardized
            let isClick = (r.width < 4 || r.height < 4) && block.kind != .pen

            if block.kind == .pen, block.points.count < 2 {
                drag = .none
                revertToolIfNeeded()
                return
            }

            if isClick {
                if block.kind.isLinear {
                    // A click with a linear tool has no direction; ignore it
                    // rather than leaving a zero-length arrow behind.
                    drag = .none
                    revertToolIfNeeded()
                    return
                }
                let size = block.kind == .frame
                    ? (store.frameSize ?? CGSize(width: 1440, height: 900))
                    : (block.kind == .text ? CGSize(width: 140, height: 24) : CGSize(width: 180, height: 110))
                block.rect = CGRect(origin: r.origin, size: size)
            } else if !block.kind.isLinear {
                block.rect = r
            }

            var blocks = store.blocks
            blocks.append(block)
            apply(blocks, name: "Add \(block.kind.label)")
            store.selection = [block.id]
            if block.kind == .text { beginEditing(block.id) }
            revertToolIfNeeded()

        case .moving(_, let snapshot):
            if snapshot != store.blocks { commitDrag(from: snapshot, name: "Move") }

        case .resizing(_, _, _, let snapshot):
            if snapshot != store.blocks { commitDrag(from: snapshot, name: "Resize") }

        case .erasing(let snapshot):
            if snapshot != store.blocks { commitDrag(from: snapshot, name: "Erase") }

        case .marquee, .panning, .none:
            break
        }
        drag = .none
        guides = []
        needsDisplay = true
    }

    /// Without the padlock the tool drops back to select after one shape, so the
    /// thing you just drew is immediately draggable.
    private func revertToolIfNeeded() {
        if !store.toolLocked { store.tool = .select }
    }

    private func eraseHit(at docPoint: CGPoint) {
        guard let hit = blockHit(at: docPoint) else { return }
        store.blocks.removeAll { $0.id == hit.id }
    }

    private func handleDoubleClick(at docPoint: CGPoint) {
        if let hit = blockHit(at: docPoint), hit.kind.takesText {
            store.selection = [hit.id]
            beginEditing(hit.id)
        } else if blockHit(at: docPoint) == nil {
            var block = makeStyledBlock(kind: .text, rect: CGRect(origin: docPoint, size: CGSize(width: 140, height: 24)))
            block.z = store.nextZ
            var blocks = store.blocks
            blocks.append(block)
            apply(blocks, name: "Add Text")
            store.selection = [block.id]
            beginEditing(block.id)
        }
    }

    private func makeStyledBlock(kind: BlockKind, rect: CGRect) -> Block {
        Block(kind: kind, rect: rect,
              stroke: store.style.stroke,
              fill: kind.takesFill ? store.style.fill : nil,
              fillStyle: store.style.fillStyle,
              strokeWidth: store.style.strokeWidth,
              cornerRadius: store.style.cornerRadius,
              opacity: store.style.opacity,
              fontSize: store.style.fontSize)
    }

    private func beginCreating(kind: BlockKind, at docPoint: CGPoint) {
        var block = makeStyledBlock(kind: kind, rect: CGRect(origin: docPoint, size: .zero))
        block.z = store.nextZ
        if kind == .pen { block.points = [docPoint] }
        if kind == .frame, let size = store.frameSize {
            block.text = FramePreset.all.first { $0.size == size }?.name ?? ""
        }
        drag = .creating(block)
    }

    // MARK: - Scroll & zoom

    override func scrollWheel(with event: NSEvent) {
        // Ctrl-scroll is the system zoom gesture and what people reach for;
        // Cmd-scroll is kept because every other canvas app honours it too.
        if event.modifierFlags.contains(.control) || event.modifierFlags.contains(.command) {
            let point = convert(event.locationInWindow, from: nil)
            let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 3
            zoom(by: 1 + delta * 0.01, around: point)
        } else {
            store.pan = CGPoint(x: store.pan.x + event.scrollingDeltaX,
                                y: store.pan.y + event.scrollingDeltaY)
            needsDisplay = true
        }
    }

    override func magnify(with event: NSEvent) {
        zoom(by: 1 + event.magnification, around: convert(event.locationInWindow, from: nil))
    }

    private func zoom(by factor: CGFloat, around viewPoint: CGPoint) {
        let docBefore = toDoc(viewPoint)
        let newZoom = max(minZoom, min(maxZoom, store.zoom * factor))
        guard abs(newZoom - store.zoom) > 0.0001 else { return }
        store.zoom = newZoom
        store.pan = CGPoint(x: viewPoint.x - docBefore.x * newZoom,
                            y: viewPoint.y - docBefore.y * newZoom)
        needsDisplay = true
    }

    func setZoom(_ value: CGFloat) {
        zoom(by: value / store.zoom, around: CGPoint(x: bounds.midX, y: bounds.midY))
    }

    /// Fits the drawing into the part of the canvas the chrome is not covering,
    /// and centres it there. The arithmetic lives in `Viewport.fitting` so it can
    /// be tested against a rail and a dock rather than eyeballed.
    func zoomToFit() {
        let content = store.blocks.isEmpty
            ? nil
            : store.blocks.map(\.bounds).reduce(CGRect.null) { $0.union($1) }
        let viewport = Viewport.fitting(content,
                                        in: bounds,
                                        insets: ChromeInsets(top: chromeInsets.top,
                                                             left: chromeInsets.left,
                                                             bottom: chromeInsets.bottom,
                                                             right: chromeInsets.right),
                                        zoomRange: minZoom...maxZoom)
        store.zoom = viewport.zoom
        store.pan = viewport.pan
        needsDisplay = true
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        guard editor == nil else { super.keyDown(with: event); return }
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if event.keyCode == 49 { isSpaceHeld = true; return }

        if let tool = Shortcuts.tool(for: chars) {
            store.tool = tool
            return
        }

        switch event.keyCode {
        case 51, 117: deleteSelection()
        case 53: escape()
        case 123: nudge(dx: -stepSize(event), dy: 0)
        case 124: nudge(dx: stepSize(event), dy: 0)
        case 125: nudge(dx: 0, dy: stepSize(event))
        case 126: nudge(dx: 0, dy: -stepSize(event))
        default: super.keyDown(with: event)
        }
    }

    override func keyUp(with event: NSEvent) {
        if event.keyCode == 49 { isSpaceHeld = false; return }
        super.keyUp(with: event)
    }

    private func stepSize(_ event: NSEvent) -> CGFloat {
        event.modifierFlags.contains(.shift) ? gridStep * 5 : gridStep
    }

    /// LSUIElement plus a nonactivating panel means no menu bar to route command
    /// keys, so the shortcuts are handled here explicitly.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let shift = event.modifierFlags.contains(.shift)

        if editor != nil, ["a", "c", "v", "x", "z"].contains(chars) { return false }

        switch chars {
        case "\r": commitEditor(); onSend?(); return true
        case "z": commitEditor(); if shift { undoManager?.redo() } else { undoManager?.undo() }; return true
        case "a": store.selection = Set(store.blocks.map(\.id)); return true
        case "d": duplicateSelection(); return true
        // Cmd+C is the canvas copy people expect. Copying the *payload* stays on
        // Cmd+Return, which is the shortcut the Copy button advertises.
        case "c": copySelection(); return true
        case "x": cutSelection(); return true
        case "v": pasteBlocks(); return true
        case "g": if shift { ungroupSelection() } else { groupSelection() }; return true
        case "0": setZoom(1); return true
        case "9": zoomToFit(); return true
        case "]": reorder(toFront: shift, forward: true); return true
        case "[": reorder(toFront: shift, forward: false); return true
        default: break
        }

        if event.keyCode == 51 { clearAll(); return true } // Cmd+Backspace clears (§2)
        return false
    }

    private func escape() {
        // Progressive escape: drop the tool first, hide the panel last, so an
        // accidental Esc never costs you the canvas.
        if store.libraryOpen { store.libraryOpen = false }
        else if store.variablesOpen { store.variablesOpen = false }
        else if store.tool != .select { store.tool = .select }
        else if !store.selection.isEmpty { store.selection = [] }
        else { PanelController.shared?.hide() }
    }

    // MARK: - Operations

    func applyStyle(_ transform: (inout Block) -> Void, name: String) {
        guard !store.selection.isEmpty else { return }
        var blocks = store.blocks
        for i in blocks.indices where store.selection.contains(blocks[i].id) {
            transform(&blocks[i])
        }
        apply(blocks, name: name)
    }

    private func nudge(dx: CGFloat, dy: CGFloat) {
        applyStyle({ block in
            block.rect = block.rect.translated(dx: dx, dy: dy)
            block.points = block.points.map { CGPoint(x: $0.x + dx, y: $0.y + dy) }
        }, name: "Move")
    }

    func deleteSelection() {
        guard !store.selection.isEmpty else { return }
        let doomed = store.selection
        apply(store.blocks.filter { !doomed.contains($0.id) }, name: "Delete")
        store.selection = []
    }

    func duplicateSelection() {
        guard !store.selection.isEmpty else { return }
        var blocks = store.blocks
        var newSelection = Set<UUID>()
        // A duplicated group stays a group, but its own — not the original's.
        var duplicatedGroups: [UUID: UUID] = [:]
        for block in store.blocks where store.selection.contains(block.id) {
            var copy = block
            copy.id = UUID()
            copy.seed = UInt64.random(in: 1...UInt64.max)
            copy.rect = copy.rect.translated(dx: gridStep * 2, dy: gridStep * 2)
            if let group = copy.groupID {
                if duplicatedGroups[group] == nil { duplicatedGroups[group] = UUID() }
                copy.groupID = duplicatedGroups[group]
            }
            copy.points = copy.points.map { CGPoint(x: $0.x + gridStep * 2, y: $0.y + gridStep * 2) }
            copy.z = (blocks.map(\.z).max() ?? 0) + 1
            blocks.append(copy)
            newSelection.insert(copy.id)
        }
        apply(blocks, name: "Duplicate")
        store.selection = newSelection
    }

    func reorder(toFront extreme: Bool, forward: Bool) {
        guard !store.selection.isEmpty else { return }
        var blocks = store.blocks
        let maxZ = blocks.map(\.z).max() ?? 0
        let minZ = blocks.map(\.z).min() ?? 0
        for i in blocks.indices where store.selection.contains(blocks[i].id) {
            if extreme { blocks[i].z = forward ? maxZ + 1 : minZ - 1 }
            else { blocks[i].z += forward ? 2 : -2 }
        }
        apply(blocks, name: forward ? "Bring Forward" : "Send Backward")
    }

    /// Drops a preset composition into the middle of the current viewport.
    func insert(_ preset: ComponentPreset) {
        let target = toDoc(CGPoint(x: bounds.midX, y: bounds.midY))
        let origin = snap(CGPoint(x: target.x - preset.size.width / 2,
                                  y: target.y - preset.size.height / 2), disabled: false)
        var blocks = store.blocks
        var z = store.nextZ
        var inserted = Set<UUID>()
        for var block in preset.build(at: origin, style: store.style) {
            block.z = z; z += 1
            inserted.insert(block.id)
            blocks.append(block)
        }
        apply(blocks, name: "Add \(preset.name)")
        store.selection = inserted
        store.libraryOpen = false
    }

    func clearAll() {
        guard !store.blocks.isEmpty else { return }
        apply([], name: "Clear Canvas")
        store.selection = []
        store.flash("Canvas cleared")
    }

    // MARK: - Undo

    /// Replaces every block, undoably.
    ///
    /// For operations that are not edits to a selection: deleting a variable
    /// rewrites the literals of everything bound to it, and that has to be
    /// undoable like any other change to the drawing.
    func replaceAll(_ blocks: [Block], name: String) { apply(blocks, name: name) }

    private func apply(_ blocks: [Block], name: String) {
        let before = store.blocks
        store.blocks = blocks
        undoManager?.registerUndo(withTarget: self) { $0.apply(before, name: name) }
        undoManager?.setActionName(name)
        needsDisplay = true
    }

    private func commitDrag(from snapshot: [Block], name: String) {
        let after = store.blocks
        store.blocks = snapshot
        apply(after, name: name)
    }

    // MARK: - Clipboard

    /// Blocks travel as JSON on a private pasteboard type, so a copy survives a
    /// relaunch and can cross between two Blockpad instances.
    private static let blockPasteboardType = NSPasteboard.PasteboardType("studio.ubik.blockpad.blocks")

    func copySelection() {
        let picked = store.selectedBlocks
        guard !picked.isEmpty, let data = try? JSONEncoder().encode(picked) else { return }
        let pasteboard = NSPasteboard(name: .general)
        pasteboard.clearContents()
        pasteboard.setData(data, forType: Self.blockPasteboardType)
        store.flash(picked.count == 1 ? "Copied" : "Copied \(picked.count)")
    }

    func cutSelection() {
        guard !store.selection.isEmpty else { return }
        copySelection()
        deleteSelection()
    }

    func pasteBlocks() {
        guard let data = NSPasteboard(name: .general).data(forType: Self.blockPasteboardType),
              let incoming = try? JSONDecoder().decode([Block].self, from: data),
              !incoming.isEmpty else { return }

        // Fresh identity for everything, or a paste would collide with the
        // blocks it came from. Parent and group links are remapped rather than
        // dropped, so a pasted group stays a group and stays its own.
        var identities: [UUID: UUID] = [:]
        var groups: [UUID: UUID] = [:]
        for block in incoming { identities[block.id] = UUID() }

        let offset = gridStep * 2
        var pasted: [Block] = []
        var z = store.nextZ
        for var block in incoming {
            block.id = identities[block.id] ?? UUID()
            if let parent = block.parentID { block.parentID = identities[parent] }
            if let group = block.groupID {
                if groups[group] == nil { groups[group] = UUID() }
                block.groupID = groups[group]
            }
            block.rect = block.rect.translated(dx: offset, dy: offset)
            block.points = block.points.map { CGPoint(x: $0.x + offset, y: $0.y + offset) }
            block.z = z
            z += 1
            pasted.append(block)
        }

        apply(store.blocks + pasted, name: "Paste")
        store.selection = Set(pasted.map(\.id))
        needsDisplay = true
    }

    // MARK: - Grouping

    func groupSelection() {
        let picked = store.selectedBlocks
        guard picked.count > 1 else { return }
        let id = UUID()
        var blocks = store.blocks
        for i in blocks.indices where store.selection.contains(blocks[i].id) {
            blocks[i].groupID = id
        }
        apply(blocks, name: "Group")
        store.flash("Grouped \(picked.count)")
        needsDisplay = true
    }

    func ungroupSelection() {
        let ids = Set(store.selectedBlocks.compactMap(\.groupID))
        guard !ids.isEmpty else { return }
        var blocks = store.blocks
        for i in blocks.indices where blocks[i].groupID.map(ids.contains) == true {
            blocks[i].groupID = nil
        }
        apply(blocks, name: "Ungroup")
        store.flash("Ungrouped")
        needsDisplay = true
    }

    /// Every block that must come along when `block` is selected or dragged.
    private func groupMates(of block: Block) -> Set<UUID> {
        guard let group = block.groupID else { return [block.id] }
        return Set(store.blocks.filter { $0.groupID == group }.map(\.id))
    }

    func undo() { commitEditor(); undoManager?.undo() }
    func redo() { commitEditor(); undoManager?.redo() }

    // MARK: - Inline text editing

    func beginEditing(_ id: UUID) {
        guard let block = store.block(id) else { return }
        commitEditor()

        let field = NSTextField(frame: editorFrame(for: block))
        field.stringValue = block.text
        field.font = BlockRenderer.canvasFont(size: BlockRenderer.fontSize(for: block) * store.zoom)
        field.textColor = store.theme.inkAdjusted(Palette.color(block.stroke))
        field.alignment = block.kind == .text ? .natural : .center
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = store.theme.color.withAlphaComponent(0.9)
        field.focusRingType = .none
        field.delegate = self
        field.target = self
        field.action = #selector(editorAction(_:))
        addSubview(field)
        editor = field
        editingBlockID = id
        window?.makeFirstResponder(field)
        needsDisplay = true
    }

    private func editorFrame(for block: Block) -> CGRect {
        let r = toView(block.bounds)
        let height = max(24, BlockRenderer.fontSize(for: block) * 1.5 * store.zoom)
        switch block.kind {
        case .text:
            return CGRect(x: r.minX, y: r.minY, width: max(80, r.width), height: height)
        case .frame:
            return CGRect(x: r.minX, y: r.minY - height - 4, width: max(90, r.width * 0.4), height: height)
        default:
            return CGRect(x: r.minX + 6, y: r.midY - height / 2, width: max(48, r.width - 12), height: height)
        }
    }

    @objc private func editorAction(_ sender: NSTextField) {
        commitEditor()
        window?.makeFirstResponder(self)
    }

    func commitEditor() {
        guard let field = editor, let id = editingBlockID else { return }
        let text = field.stringValue
        editor = nil
        editingBlockID = nil
        field.removeFromSuperview()

        guard var block = store.block(id) else { return }
        let isEmpty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // Empty text blocks are litter; drop them rather than leaving ghosts.
        if block.kind == .text, isEmpty {
            apply(store.blocks.filter { $0.id != id }, name: "Delete Text")
            store.selection = []
            needsDisplay = true
            return
        }

        guard block.text != text else { needsDisplay = true; return }
        block.text = text
        if block.kind == .text {
            block.rect = CGRect(origin: block.rect.origin,
                                size: BlockRenderer.measure(text, size: BlockRenderer.fontSize(for: block)))
        }
        var blocks = store.blocks
        if let i = blocks.firstIndex(where: { $0.id == id }) { blocks[i] = block }
        apply(blocks, name: "Edit Text")
        needsDisplay = true
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        discardCursorRects()
        let cursor: NSCursor
        switch store.tool {
        case .select: cursor = .arrow
        case .hand: cursor = .openHand
        case .eraser: cursor = .disappearingItem
        case .draw: cursor = .crosshair
        }
        addCursorRect(bounds, cursor: cursor)
    }
}

extension CanvasView: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            commitEditor()
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }
}

// MARK: - Drag state

private enum DragState {
    case none
    case creating(Block)
    case moving(origin: CGPoint, snapshot: [Block])
    case resizing(id: UUID, handle: Handle, original: CGRect, snapshot: [Block])
    case marquee(start: CGPoint, current: CGPoint)
    case erasing(snapshot: [Block])
    case panning(start: CGPoint, originalPan: CGPoint)
}

enum Handle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    /// Connectors only. Sits on the bow and sets how far it leaves the chord.
    case curve
    /// Closed shapes only. Sits above the box and spins it.
    case rotate

    func point(in r: CGRect) -> CGPoint {
        switch self {
        case .topLeft:     return CGPoint(x: r.minX, y: r.minY)
        case .top:         return CGPoint(x: r.midX, y: r.minY)
        case .topRight:    return CGPoint(x: r.maxX, y: r.minY)
        case .right:       return CGPoint(x: r.maxX, y: r.midY)
        case .bottomRight: return CGPoint(x: r.maxX, y: r.maxY)
        case .bottom:      return CGPoint(x: r.midX, y: r.maxY)
        case .bottomLeft:  return CGPoint(x: r.minX, y: r.maxY)
        case .left:        return CGPoint(x: r.minX, y: r.midY)
        case .curve:       return CGPoint(x: r.midX, y: r.midY)
        case .rotate:      return CGPoint(x: r.midX, y: r.minY)
        }
    }

    /// The corner that stays put while this handle is dragged.
    func anchor(in r: CGRect) -> CGPoint {
        switch self {
        case .topLeft:     return CGPoint(x: r.maxX, y: r.maxY)
        case .topRight:    return CGPoint(x: r.minX, y: r.maxY)
        case .bottomLeft:  return CGPoint(x: r.maxX, y: r.minY)
        case .bottomRight: return CGPoint(x: r.minX, y: r.minY)
        case .top, .bottom, .left, .right, .curve, .rotate: return CGPoint(x: r.minX, y: r.minY)
        }
    }

    func resize(_ r: CGRect, to p: CGPoint) -> CGRect {
        var minX = r.minX, minY = r.minY, maxX = r.maxX, maxY = r.maxY
        switch self {
        case .topLeft:     minX = p.x; minY = p.y
        case .top:         minY = p.y
        case .topRight:    maxX = p.x; minY = p.y
        case .right:       maxX = p.x
        case .bottomRight: maxX = p.x; maxY = p.y
        case .bottom:      maxY = p.y
        case .bottomLeft:  minX = p.x; maxY = p.y
        case .left:        minX = p.x
        case .curve, .rotate: break
        }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY),
                      width: abs(maxX - minX), height: abs(maxY - minY))
    }
}
