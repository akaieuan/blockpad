import AppKit
import BlockpadKit

enum PayloadMode: String, CaseIterable, Identifiable {
    case tree
    case treeAndImage
    case image

    var id: String { rawValue }

    /// What this mode asks to send, independent of what any target can take.
    var shape: PayloadShape {
        switch self {
        case .tree: return .textOnly
        case .treeAndImage: return .textAndImage
        case .image: return .imageOnly
        }
    }

    var label: String {
        switch self {
        case .tree: return "Tree only"
        case .treeAndImage: return "Tree + image"
        case .image: return "Image only"
        }
    }

    /// What the mode is for. Deliberately not a token count: the old labels
    /// hardcoded "~120 tok" and friends, which were a guess for one particular
    /// scene and wrong for every other one — and text tokens cannot be
    /// estimated honestly without asking the API.
    var detail: String {
        switch self {
        case .tree: return "structure"
        case .treeAndImage: return "structure + feel"
        case .image: return "annotated"
        }
    }

    /// A size the app can actually stand behind, for the scene in front of it.
    /// The tree is quoted in characters because that is what is knowable
    /// locally; the image in tokens because that side is pure arithmetic.
    func measurement(tree: String, imageSize: CGSize) -> String {
        switch self {
        case .tree:
            return "\(tree.count) chars"
        case .image:
            return "~\(SketchExport.imageTokens(for: imageSize)) tok"
        case .treeAndImage:
            return "\(tree.count) chars + ~\(SketchExport.imageTokens(for: imageSize)) tok"
        }
    }
}

private extension Int {
    func quantized(to step: Int) -> Int { step <= 1 ? self : (self / step) * step }
}

enum SketchExport {

    static let padding: CGFloat = 32

    /// What an image of this size costs a Claude request.
    ///
    /// Anything longer than 1568px on its long edge is resized first, and the
    /// charge is (width x height) / 750 on the *resized* dimensions — skipping
    /// the resize overstates a large canvas several times over.
    static func imageTokens(for size: CGSize) -> Int {
        guard size.width > 0, size.height > 0 else { return 0 }
        let longEdge = max(size.width, size.height)
        let scale = min(1, 1568 / longEdge)
        return Int(((size.width * scale).rounded() * (size.height * scale).rounded() / 750).rounded())
    }

    // MARK: - Image

    static func contentBounds(_ blocks: [Block]) -> CGRect {
        let rects = blocks.map(\.bounds)
        guard !rects.isEmpty else { return CGRect(x: 0, y: 0, width: 400, height: 300) }
        // Frame labels sit above the sheet, so leave room or they get cropped.
        let labelRoom: CGFloat = blocks.contains { $0.kind == .frame } ? 24 : 0
        var union = rects.reduce(CGRect.null) { $0.union($1) }
        union.origin.y -= labelRoom
        union.size.height += labelRoom
        return union.insetBy(dx: -padding, dy: -padding)
    }

    static func renderImage(_ blocks: [Block], options: RenderOptions = RenderOptions(), scale: CGFloat = 2) -> NSImage? {
        let bounds = contentBounds(blocks)
        guard bounds.width > 1, bounds.height > 1 else { return nil }

        let pixelWidth = Int(bounds.width * scale)
        let pixelHeight = Int(bounds.height * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth, pixelsHigh: pixelHeight,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { return nil }

        ctx.saveGState()
        ctx.scaleBy(x: scale, y: scale)
        // Flip into document space (y-down) to match the canvas.
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: -bounds.minX, y: -bounds.minY)

        ctx.setFillColor(options.theme.color.cgColor)
        ctx.fill(bounds)

        let sorted = blocks.sorted { a, b in
            if (a.kind == .frame) != (b.kind == .frame) { return a.kind == .frame }
            return a.z < b.z
        }
        for block in sorted {
            BlockRenderer.draw(block, in: ctx, zoom: 1, options: options)
        }
        ctx.restoreGState()

        let image = NSImage(size: NSSize(width: bounds.width, height: bounds.height))
        image.addRepresentation(rep)
        return image
    }

    static func renderPNGData(_ blocks: [Block], options: RenderOptions = RenderOptions(), scale: CGFloat = 2) -> Data? {
        guard let image = renderImage(blocks, options: options, scale: scale),
              let rep = image.representations.first as? NSBitmapImageRep else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Tree (§5)

    /// Serializes the scene graph to text locally, no inference. Parenthood is
    /// inferred from containment because that is how you actually draw — you put
    /// a box inside a frame, you don't declare a relationship.
    static func tree(_ blocks: [Block], template: StyleTemplate? = nil) -> String {
        let visible = blocks.filter { $0.kind != .redact }
        guard !visible.isEmpty else { return "" }

        let roots = visible.filter { parent(of: $0, in: visible) == nil }
        var lines: [String] = []
        var signatures: [UUID: String] = [:]
        for block in visible { signatures[block.id] = signature(block, in: visible) }
        // Roots are placed relative to the drawing's own top-left, so the tree
        // never leaks wherever on the infinite canvas you happened to be.
        let contentOrigin = visible.map(\.bounds).reduce(CGRect.null) { $0.union($1) }.origin
        emitSiblings(roots, in: visible, signatures: signatures, depth: 0,
                     contentOrigin: contentOrigin, into: &lines)

        // A template with rules leads the tree, because it changes how
        // everything below it should be read: an agent told `accessible` should
        // not offer a 3:1 grey. Templates that only set defaults say nothing —
        // their effect is already in the hex values.
        if let template, template.isChecked {
            lines.insert("template \(template.id)  # \(template.summary)", at: 0)
        }
        return lines.joined(separator: "\n")
    }

    /// Six identical rows should serialize as one line with a count, not six
    /// lines — that repetition is most of the gap between the tree and the
    /// ~120-token target in §5.
    private static func emitSiblings(_ siblings: [Block], in blocks: [Block],
                                     signatures: [UUID: String], depth: Int,
                                     contentOrigin: CGPoint,
                                     into lines: inout [String]) {
        let list = ordered(siblings)
        var i = 0
        while i < list.count {
            var run = 1
            let sig = signatures[list[i].id]
            while i + run < list.count, signatures[list[i + run].id] == sig { run += 1 }
            let group = Array(list[i..<(i + run)])
            emit(list[i], in: blocks, signatures: signatures, depth: depth,
                 group: group, contentOrigin: contentOrigin, into: &lines)
            i += run
        }
    }

    /// Identity for run-collapsing: same kind, size, text, colour and — because
    /// a row of checkboxes is only "the same row" if its contents match — the
    /// same child structure. Position is deliberately excluded so a stack of
    /// identical rows still collapses.
    private static func signature(_ block: Block, in blocks: [Block]) -> String {
        let r = block.rect.standardized
        let children = ordered(blocks.filter { parent(of: $0, in: blocks)?.id == block.id })
        let childSignature = children.map { signature($0, in: blocks) }.joined(separator: "|")
        return "\(block.kind.rawValue):\(Int(r.width.rounded()))x\(Int(r.height.rounded())):\(block.text):\(block.stroke):\(block.fill ?? "-"):[\(childSignature)]"
    }

    private static func parent(of block: Block, in blocks: [Block]) -> Block? {
        let r = block.rect.standardized
        // Smallest strict container wins, so nesting depth comes out right.
        return blocks
            .filter { $0.id != block.id }
            .filter { candidate in
                let cr = candidate.rect.standardized
                guard cr.width * cr.height > r.width * r.height else { return false }
                return cr.insetBy(dx: -2, dy: -2).contains(r)
            }
            .min { a, b in
                let ar = a.rect.standardized, br = b.rect.standardized
                return ar.width * ar.height < br.width * br.height
            }
    }

    /// Reading order: top to bottom, then left to right, with a row tolerance so
    /// a row of side-by-side buttons doesn't get scrambled by a few pixels.
    private static func ordered(_ blocks: [Block]) -> [Block] {
        blocks.sorted { a, b in
            let ar = a.rect.standardized, br = b.rect.standardized
            if abs(ar.minY - br.minY) > 12 { return ar.minY < br.minY }
            return ar.minX < br.minX
        }
    }

    private static func emit(_ block: Block, in blocks: [Block], signatures: [UUID: String],
                             depth: Int, group: [Block], contentOrigin: CGPoint,
                             into lines: inout [String]) {
        let indent = String(repeating: "  ", count: depth)
        let r = block.rect.standardized
        let repeatCount = group.count
        let groupBounds = group.map { $0.rect.standardized }.reduce(CGRect.null) { $0.union($1) }
        var parts: [String] = []

        switch block.kind {
        case .frame:
            parts.append("Frame \(Int(r.width.rounded()))x\(Int(r.height.rounded()))")
        case .text:
            parts.append("Text")
        case .box:
            parts.append("Box \(Int(r.width.rounded()))x\(Int(r.height.rounded()))")
        case .arrow, .line:
            // A connector's bounding box says nothing about which way it runs,
            // and two arrows pointing opposite ways have the same box. What an
            // agent needs is the heading, so emit that instead of a size.
            parts.append("\(block.kind.label) \(Int(Connector.length(of: block.rect).rounded()))")
            let degrees = Connector.angle(of: block.rect) * 180 / .pi
            let normalized = Int((degrees < 0 ? degrees + 360 : degrees).rounded())
                .quantized(to: 1)
            parts.append("\(normalized)°")
        default:
            parts.append(block.kind.label)
        }

        if repeatCount > 1 { parts.append("×\(repeatCount)") }

        // Position is never optional. The old code emitted a word anchor only
        // when something sat within 6% of a parent edge and appended nothing
        // otherwise — so a box floating mid-container carried no position at
        // all, which is most boxes anyone actually draws.
        let reference: CGPoint = parent(of: block, in: blocks)
            .map { $0.rect.standardized.origin } ?? contentOrigin
        let offsetX = Int((groupBounds.minX - reference.x).rounded())
        let offsetY = Int((groupBounds.minY - reference.y).rounded())
        parts.append("@\(offsetX),\(offsetY)")

        // A run collapses to a count plus the step between members, so ×6 stays
        // cheap without throwing away where the other five are.
        if repeatCount > 1, group.count > 1 {
            let first = group[0].rect.standardized
            let second = group[1].rect.standardized
            let stepX = Int((second.minX - first.minX).rounded())
            let stepY = Int((second.minY - first.minY).rounded())
            parts.append("step \(stepX),\(stepY)")
        }

        // Word anchors still earn their place when they apply — "full-height"
        // says something coordinates do not.
        if block.kind != .frame, let anchor = anchor(of: groupBounds, in: block, blocks: blocks) {
            parts.append(anchor)
        }
        if !block.text.isEmpty { parts.append("\"\(block.text)\"") }
        // Hex, not a palette name. `#55677A` is a value the receiving agent can
        // paste into CSS; `[slate]` was a lookup it could not perform. Only
        // emitted when it differs from the default, to keep the line short.
        if block.stroke != Palette.defaultStroke {
            parts.append("stroke \(block.stroke)")
        }
        if let fill = block.fill, block.fillStyle != .none {
            parts.append("fill \(fill)")
        }
        if abs(block.cornerRadius - 10) > 0.5, !block.kind.isLinear {
            parts.append("r\(Int(block.cornerRadius.rounded()))")
        }
        if block.kind.isLinear, block.curve != 0 {
            parts.append("bow \(Int((block.curve * 100).rounded()))%")
        }
        // The tilt names itself. An agent that ignores it still has a correct
        // flat layout, which is the right failure mode — the plane is
        // presentation, the rect is structure.
        if let plane = block.transform?.token {
            parts.append(plane)
        }

        lines.append(indent + parts.joined(separator: "  "))

        let children = blocks.filter { parent(of: $0, in: blocks)?.id == block.id }
        emitSiblings(children, in: blocks, signatures: signatures, depth: depth + 1,
                     contentOrigin: contentOrigin, into: &lines)
    }

    /// Where the block sits inside its parent, in words the model can act on.
    private static func anchor(of rect: CGRect, in block: Block, blocks: [Block]) -> String? {
        guard let parent = parent(of: block, in: blocks) else { return nil }
        let r = rect.isNull ? block.rect.standardized : rect
        let p = parent.rect.standardized
        guard p.width > 0, p.height > 0 else { return nil }

        var words: [String] = []
        let widthRatio = r.width / p.width
        let heightRatio = r.height / p.height
        let leftGap = (r.minX - p.minX) / p.width
        let rightGap = (p.maxX - r.maxX) / p.width
        let topGap = (r.minY - p.minY) / p.height
        let bottomGap = (p.maxY - r.maxY) / p.height

        if widthRatio > 0.9 { words.append("full-width") }
        else if leftGap < 0.06 { words.append("left") }
        else if rightGap < 0.06 { words.append("right") }

        if heightRatio > 0.9 { words.append("full-height") }
        else if topGap < 0.06 { words.append("top") }
        else if bottomGap < 0.06 { words.append("bottom") }

        return words.isEmpty ? nil : "@" + words.joined(separator: "-")
    }

    // MARK: - Pasteboard

    @discardableResult
    static func copyToPasteboard(_ blocks: [Block], mode: PayloadMode,
                                 options: RenderOptions = RenderOptions(),
                                 template: StyleTemplate? = nil) -> String {
        guard !blocks.isEmpty else { return "Nothing to copy" }

        let pb = NSPasteboard.general
        pb.clearContents()

        // One item carrying both representations lets the receiving app pick the
        // richest form it supports — editors take the image, terminals the text.
        let item = NSPasteboardItem()
        let text = tree(blocks, template: template)

        switch mode {
        case .tree:
            item.setString(text, forType: .string)
        case .image:
            guard let png = renderPNGData(blocks, options: options) else { return "Nothing to copy" }
            item.setData(png, forType: .png)
        case .treeAndImage:
            // PNG first. Pasteboard type order is priority order, and writing
            // the string first meant every app took the text and silently
            // dropped the image.
            if let png = renderPNGData(blocks, options: options) { item.setData(png, forType: .png) }
            item.setString(text, forType: .string)
        }

        pb.writeObjects([item])

        switch mode {
        case .tree: return "Copied tree · \(text.split(separator: "\n").count) lines"
        case .image: return "Copied image"
        case .treeAndImage: return "Copied tree + image"
        }
    }
}
