import AppKit
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
    private var hoverHandle: Handle?

    private let gridStep: CGFloat = 8
    private let handleSize: CGFloat = 7
    private let minZoom: CGFloat = 0.25
    private let maxZoom: CGFloat = 4

    // MARK: - Init

    init(store: SketchStore) {
        self.store = store
        super.init(frame: .zero)
        wantsLayer = true

        // Any model change repaints. Cheap at this scale and keeps the AppKit
        // view honest about SwiftUI-side edits from the toolbar.
        store.$blocks.sink { [weak self] _ in self?.needsDisplay = true }.store(in: &cancellables)
        store.$selection.sink { [weak self] _ in self?.needsDisplay = true }.store(in: &cancellables)
        store.$tool.sink { [weak self] _ in
            self?.needsDisplay = true
            self?.window?.invalidateCursorRects(for: self!)
        }.store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Coordinate transform

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

        BlockRenderer.drawBackground(in: ctx, visibleDocRect: visibleDocRect, zoom: store.zoom)

        for block in store.sorted {
            if block.id == editingBlockID { continue }
            BlockRenderer.draw(block, in: ctx, zoom: store.zoom)
        }
        if case .creating(let block) = drag {
            BlockRenderer.draw(block, in: ctx, zoom: store.zoom)
        }
        ctx.restoreGState()

        drawSelectionChrome(in: ctx)
    }

    /// Selection UI is drawn in view space so its weight stays constant at any zoom.
    private func drawSelectionChrome(in ctx: CGContext) {
        let selected = store.blocks.filter { store.selection.contains($0.id) }

        ctx.saveGState()
        ctx.setStrokeColor(Palette.selection.cgColor)
        ctx.setLineWidth(1)
        for block in selected {
            let r = toView(block.rect.standardized).insetBy(dx: -3, dy: -3)
            ctx.stroke(r)
        }
        ctx.restoreGState()

        if let only = selected.first, selected.count == 1, only.kind != .text {
            let r = toView(only.rect.standardized).insetBy(dx: -3, dy: -3)
            ctx.saveGState()
            for handle in Handle.allCases {
                let h = handleRect(handle, in: r)
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.setStrokeColor(Palette.selection.cgColor)
                ctx.setLineWidth(1)
                ctx.fill(h)
                ctx.stroke(h)
            }
            ctx.restoreGState()
        }

        if case .marquee(let start, let current) = drag {
            let r = CGRect(x: min(start.x, current.x), y: min(start.y, current.y),
                           width: abs(current.x - start.x), height: abs(current.y - start.y))
            ctx.saveGState()
            ctx.setFillColor(Palette.selection.withAlphaComponent(0.10).cgColor)
            ctx.setStrokeColor(Palette.selection.withAlphaComponent(0.7).cgColor)
            ctx.setLineWidth(1)
            ctx.fill(r)
            ctx.stroke(r)
            ctx.restoreGState()
        }
    }

    private func handleRect(_ handle: Handle, in r: CGRect) -> CGRect {
        let p = handle.point(in: r)
        return CGRect(x: p.x - handleSize / 2, y: p.y - handleSize / 2,
                      width: handleSize, height: handleSize)
    }

    // MARK: - Hit testing

    private func blockHit(at docPoint: CGPoint) -> Block? {
        // Topmost first; frames last so clicking inside a frame grabs its children.
        for block in store.sorted.reversed() {
            let r = block.rect.standardized
            switch block.kind {
            case .frame:
                // Frames are grabbed by their edge or their label, not their body,
                // otherwise they swallow every click inside the sheet.
                let outer = r.insetBy(dx: -6, dy: -6)
                let inner = r.insetBy(dx: 6, dy: 6)
                let labelStrip = CGRect(x: r.minX, y: r.minY - 22, width: max(60, r.width * 0.4), height: 22)
                if (outer.contains(docPoint) && !inner.contains(docPoint)) || labelStrip.contains(docPoint) {
                    return block
                }
            default:
                if r.insetBy(dx: -3, dy: -3).contains(docPoint) { return block }
            }
        }
        return nil
    }

    private func handleHit(at viewPoint: CGPoint) -> (UUID, Handle)? {
        guard store.selection.count == 1,
              let id = store.selection.first,
              let block = store.block(id), block.kind != .text else { return nil }
        let r = toView(block.rect.standardized).insetBy(dx: -3, dy: -3)
        for handle in Handle.allCases where handleRect(handle, in: r).insetBy(dx: -2, dy: -2).contains(viewPoint) {
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

        if event.clickCount == 2 {
            handleDoubleClick(at: docPoint)
            return
        }

        // Space-drag or middle-drag pans.
        if isSpaceHeld {
            drag = .panning(start: viewPoint, originalPan: store.pan)
            return
        }

        if let kind = store.tool.kind {
            beginCreating(kind: kind, at: snap(docPoint, disabled: noSnap))
            return
        }

        if let (id, handle) = handleHit(at: viewPoint), let block = store.block(id) {
            drag = .resizing(id: id, handle: handle, original: block.rect.standardized, snapshot: store.blocks)
            return
        }

        if let hit = blockHit(at: docPoint) {
            if event.modifierFlags.contains(.shift) {
                if store.selection.contains(hit.id) { store.selection.remove(hit.id) }
                else { store.selection.insert(hit.id) }
            } else if !store.selection.contains(hit.id) {
                store.selection = [hit.id]
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
            let start = block.rect.origin
            var end = snap(docPoint, disabled: noSnap)
            if constrain {
                let side = max(abs(end.x - start.x), abs(end.y - start.y))
                end = CGPoint(x: start.x + side * (end.x < start.x ? -1 : 1),
                              y: start.y + side * (end.y < start.y ? -1 : 1))
            }
            block.rect = CGRect(x: start.x, y: start.y, width: end.x - start.x, height: end.y - start.y)
            drag = .creating(block)

        case .moving(let origin, let snapshot):
            var dx = docPoint.x - origin.x
            var dy = docPoint.y - origin.y
            if constrain {
                if abs(dx) > abs(dy) { dy = 0 } else { dx = 0 }
            }
            var updated = snapshot
            for i in updated.indices where store.selection.contains(updated[i].id) {
                let base = snapshot[i].rect
                var moved = base.offsetBy(dx: dx, dy: dy)
                if !noSnap {
                    let snapped = snap(moved.origin, disabled: false)
                    moved.origin = snapped
                }
                updated[i].rect = moved
            }
            store.blocks = updated

        case .resizing(let id, let handle, let original, let snapshot):
            guard let index = store.blocks.firstIndex(where: { $0.id == id }) else { return }
            let p = snap(docPoint, disabled: noSnap)
            var blocks = snapshot
            blocks[index].rect = handle.resize(original, to: p)
            store.blocks = blocks

        case .marquee(let start, _):
            drag = .marquee(start: start, current: viewPoint)
            let r = CGRect(x: min(start.x, viewPoint.x), y: min(start.y, viewPoint.y),
                           width: abs(viewPoint.x - start.x), height: abs(viewPoint.y - start.y))
            let docRect = CGRect(origin: toDoc(r.origin),
                                 size: CGSize(width: r.width / store.zoom, height: r.height / store.zoom))
            store.selection = Set(store.blocks.filter { docRect.intersects($0.rect.standardized) }.map(\.id))

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
            // A click rather than a drag: give the shape a sensible default size
            // instead of a zero-area sliver.
            if r.width < 4 || r.height < 4 {
                if block.kind == .text {
                    block.rect = CGRect(origin: r.origin, size: CGSize(width: 120, height: 22))
                } else {
                    let size = block.kind == .frame ? (store.frameSize ?? CGSize(width: 1440, height: 900))
                                                    : CGSize(width: 160, height: 96)
                    block.rect = CGRect(origin: r.origin, size: size)
                }
            } else {
                block.rect = r
            }
            var blocks = store.blocks
            blocks.append(block)
            apply(blocks, name: "Add \(block.kind.label)")
            store.selection = [block.id]
            if block.kind == .text { beginEditing(block.id) }

        case .moving(_, let snapshot):
            if snapshot != store.blocks { commitDrag(from: snapshot, name: "Move") }

        case .resizing(_, _, _, let snapshot):
            if snapshot != store.blocks { commitDrag(from: snapshot, name: "Resize") }

        case .marquee, .panning, .none:
            break
        }
        drag = .none
        needsDisplay = true
    }

    private func handleDoubleClick(at docPoint: CGPoint) {
        if let hit = blockHit(at: docPoint), hit.kind != .redact {
            store.selection = [hit.id]
            beginEditing(hit.id)
        } else {
            var block = Block(kind: .text, rect: CGRect(origin: docPoint, size: CGSize(width: 120, height: 22)))
            block.colorIndex = store.colorIndex
            block.strokeIndex = store.strokeIndex
            block.z = store.nextZ
            var blocks = store.blocks
            blocks.append(block)
            apply(blocks, name: "Add Text")
            store.selection = [block.id]
            beginEditing(block.id)
        }
    }

    private func beginCreating(kind: BlockKind, at docPoint: CGPoint) {
        var block = Block(kind: kind, rect: CGRect(origin: docPoint, size: .zero))
        block.colorIndex = store.colorIndex
        block.strokeIndex = store.strokeIndex
        block.z = store.nextZ
        if kind == .frame, let size = store.frameSize {
            block.text = FramePreset.all.first { $0.size == size }?.name ?? ""
        }
        drag = .creating(block)
    }

    // MARK: - Scroll & zoom

    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.command) {
            let point = convert(event.locationInWindow, from: nil)
            zoom(by: 1 + event.scrollingDeltaY * 0.01, around: point)
        } else {
            store.pan = CGPoint(x: store.pan.x + event.scrollingDeltaX,
                                y: store.pan.y + event.scrollingDeltaY)
            needsDisplay = true
        }
    }

    override func magnify(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        zoom(by: 1 + event.magnification, around: point)
    }

    private func zoom(by factor: CGFloat, around viewPoint: CGPoint) {
        let docBefore = toDoc(viewPoint)
        let newZoom = max(minZoom, min(maxZoom, store.zoom * factor))
        guard newZoom != store.zoom else { return }
        store.zoom = newZoom
        // Keep the point under the cursor pinned.
        store.pan = CGPoint(x: viewPoint.x - docBefore.x * newZoom,
                            y: viewPoint.y - docBefore.y * newZoom)
        needsDisplay = true
    }

    func zoomToFit() {
        guard !store.blocks.isEmpty else {
            store.zoom = 1
            store.pan = .zero
            needsDisplay = true
            return
        }
        let union = store.blocks.map { $0.rect.standardized }
            .reduce(CGRect.null) { $0.union($1) }
            .insetBy(dx: -48, dy: -48)
        let scale = min(bounds.width / union.width, bounds.height / union.height)
        store.zoom = max(minZoom, min(maxZoom, scale))
        store.pan = CGPoint(x: (bounds.width - union.width * store.zoom) / 2 - union.minX * store.zoom,
                            y: (bounds.height - union.height * store.zoom) / 2 - union.minY * store.zoom)
        needsDisplay = true
    }

    // MARK: - Keyboard

    private var isSpaceHeld = false

    override func flagsChanged(with event: NSEvent) {
        super.flagsChanged(with: event)
    }

    override func keyDown(with event: NSEvent) {
        guard editor == nil else { super.keyDown(with: event); return }
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if event.keyCode == 49 { // space
            isSpaceHeld = true
            return
        }

        switch chars {
        case "v": store.tool = .select; return
        case "f": store.tool = .draw(.frame); return
        case "b": store.tool = .draw(.box); return
        case "t": store.tool = .draw(.text); return
        case "1", "2", "3", "4", "5":
            if let n = Int(chars) { applyColor(n - 1) }
            return
        default: break
        }

        switch event.keyCode {
        case 51, 117: // delete, forward delete
            deleteSelection()
        case 53: // esc
            escape()
        case 123: nudge(dx: -stepSize(event), dy: 0)
        case 124: nudge(dx: stepSize(event), dy: 0)
        case 125: nudge(dx: 0, dy: stepSize(event))
        case 126: nudge(dx: 0, dy: -stepSize(event))
        default:
            super.keyDown(with: event)
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

        // Let the text editor keep the standard editing shortcuts.
        if editor != nil, ["a", "c", "v", "x", "z"].contains(chars) { return false }

        switch chars {
        case "\r":
            commitEditor()
            onSend?()
            return true
        case "z":
            commitEditor()
            if shift { undoManager?.redo() } else { undoManager?.undo() }
            return true
        case "a":
            store.selection = Set(store.blocks.map(\.id))
            return true
        case "d":
            duplicateSelection()
            return true
        case "c":
            onCopy?()
            return true
        case "0":
            store.zoom = 1; needsDisplay = true
            return true
        case "9":
            zoomToFit()
            return true
        default: break
        }

        if event.keyCode == 51 { // Cmd+Backspace clears, explicitly (§2)
            clearAll()
            return true
        }
        return false
    }

    var onCopy: (() -> Void)?

    private func escape() {
        // Progressive escape: drop the tool first, hide the panel second, so an
        // accidental Esc never costs you the canvas.
        if store.tool != .select {
            store.tool = .select
        } else if !store.selection.isEmpty {
            store.selection = []
        } else {
            PanelController.shared?.hide()
        }
    }

    // MARK: - Editing operations

    private func applyColor(_ index: Int) {
        store.colorIndex = index
        guard !store.selection.isEmpty else { return }
        var blocks = store.blocks
        for i in blocks.indices where store.selection.contains(blocks[i].id) {
            blocks[i].colorIndex = index
        }
        apply(blocks, name: "Color")
    }

    func applyStroke(_ index: Int) {
        guard !store.selection.isEmpty else { return }
        var blocks = store.blocks
        for i in blocks.indices where store.selection.contains(blocks[i].id) {
            blocks[i].strokeIndex = index
        }
        apply(blocks, name: "Stroke")
    }

    private func nudge(dx: CGFloat, dy: CGFloat) {
        guard !store.selection.isEmpty else { return }
        var blocks = store.blocks
        for i in blocks.indices where store.selection.contains(blocks[i].id) {
            blocks[i].rect = blocks[i].rect.offsetBy(dx: dx, dy: dy)
        }
        apply(blocks, name: "Move")
    }

    private func deleteSelection() {
        guard !store.selection.isEmpty else { return }
        let doomed = store.selection
        let blocks = store.blocks.filter { !doomed.contains($0.id) }
        apply(blocks, name: "Delete")
        store.selection = []
    }

    private func duplicateSelection() {
        guard !store.selection.isEmpty else { return }
        var blocks = store.blocks
        var newSelection = Set<UUID>()
        for block in store.blocks where store.selection.contains(block.id) {
            var copy = block
            copy.id = UUID()
            copy.seed = UInt64.random(in: 1...UInt64.max)
            copy.rect = copy.rect.offsetBy(dx: gridStep * 2, dy: gridStep * 2)
            copy.z = (blocks.map(\.z).max() ?? 0) + 1
            blocks.append(copy)
            newSelection.insert(copy.id)
        }
        apply(blocks, name: "Duplicate")
        store.selection = newSelection
    }

    func clearAll() {
        guard !store.blocks.isEmpty else { return }
        apply([], name: "Clear Canvas")
        store.selection = []
        store.flash("Canvas cleared")
    }

    // MARK: - Undo

    private func apply(_ blocks: [Block], name: String) {
        let before = store.blocks
        store.blocks = blocks
        undoManager?.registerUndo(withTarget: self) { target in
            target.apply(before, name: name)
        }
        undoManager?.setActionName(name)
        needsDisplay = true
    }

    private func commitDrag(from snapshot: [Block], name: String) {
        let after = store.blocks
        store.blocks = snapshot
        apply(after, name: name)
    }

    // MARK: - Inline text editing

    func beginEditing(_ id: UUID) {
        guard let block = store.block(id) else { return }
        commitEditor()

        let field = NSTextField(frame: editorFrame(for: block))
        field.stringValue = block.text
        field.font = BlockRenderer.canvasFont(size: BlockRenderer.fontSize(forStroke: block.strokeIndex) * store.zoom)
        field.textColor = Palette.color(block.colorIndex)
        field.alignment = block.kind == .box ? .center : .natural
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = NSColor.white.withAlphaComponent(0.85)
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
        let r = toView(block.rect.standardized)
        let height = max(22, BlockRenderer.fontSize(forStroke: block.strokeIndex) * 1.5 * store.zoom)
        switch block.kind {
        case .box:
            return CGRect(x: r.minX + 4, y: r.midY - height / 2, width: max(40, r.width - 8), height: height)
        case .frame:
            return CGRect(x: r.minX, y: r.minY - height - 4, width: max(80, r.width * 0.4), height: height)
        default:
            return CGRect(x: r.minX, y: r.minY, width: max(60, r.width), height: height)
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
        if block.text != text {
            block.text = text
            // Empty text blocks are litter; drop them rather than leaving ghosts.
            if block.kind == .text && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                apply(store.blocks.filter { $0.id != id }, name: "Delete Text")
                store.selection = []
                return
            }
            if block.kind == .text {
                let size = BlockRenderer.measure(text, strokeIndex: block.strokeIndex)
                block.rect = CGRect(origin: block.rect.origin, size: size)
            }
            var blocks = store.blocks
            if let i = blocks.firstIndex(where: { $0.id == id }) { blocks[i] = block }
            apply(blocks, name: "Edit Text")
        } else if block.kind == .text && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            apply(store.blocks.filter { $0.id != id }, name: "Delete Text")
            store.selection = []
        }
        needsDisplay = true
    }

    // MARK: - Cursor

    override func resetCursorRects() {
        discardCursorRects()
        let cursor: NSCursor = store.tool.kind == nil ? .arrow : .crosshair
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
    case panning(start: CGPoint, originalPan: CGPoint)
}

enum Handle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left

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
        }
        return CGRect(x: min(minX, maxX), y: min(minY, maxY),
                      width: abs(maxX - minX), height: abs(maxY - minY))
    }
}
