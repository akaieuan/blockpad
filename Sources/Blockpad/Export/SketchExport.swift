import AppKit

enum PayloadMode: String, CaseIterable, Identifiable {
    case tree
    case treeAndImage
    case image

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tree: return "Tree only"
        case .treeAndImage: return "Tree + image"
        case .image: return "Image only"
        }
    }

    var detail: String {
        switch self {
        case .tree: return "~120 tok · structure"
        case .treeAndImage: return "~1.8k tok · structure + feel"
        case .image: return "~1.7k tok · annotated"
        }
    }
}

enum SketchExport {

    static let padding: CGFloat = 32

    // MARK: - Image

    static func contentBounds(_ blocks: [Block]) -> CGRect {
        let rects = blocks.map { $0.rect.standardized }
        guard !rects.isEmpty else { return CGRect(x: 0, y: 0, width: 400, height: 300) }
        // Frames define the crop when present; otherwise fall back to everything.
        let frames = blocks.filter { $0.kind == .frame }.map { $0.rect.standardized }
        let base = frames.isEmpty ? rects.reduce(CGRect.null) { $0.union($1) }
                                  : frames.reduce(CGRect.null) { $0.union($1) }
        let all = rects.reduce(CGRect.null) { $0.union($1) }
        return base.union(all).insetBy(dx: -padding, dy: -padding)
    }

    static func renderImage(_ blocks: [Block], scale: CGFloat = 2) -> NSImage? {
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

        ctx.setFillColor(Palette.paper.cgColor)
        ctx.fill(bounds)

        let sorted = blocks.sorted { a, b in
            if (a.kind == .frame) != (b.kind == .frame) { return a.kind == .frame }
            return a.z < b.z
        }
        for block in sorted {
            BlockRenderer.draw(block, in: ctx, zoom: 1)
        }
        ctx.restoreGState()

        let image = NSImage(size: NSSize(width: bounds.width, height: bounds.height))
        image.addRepresentation(rep)
        return image
    }

    static func renderPNGData(_ blocks: [Block], scale: CGFloat = 2) -> Data? {
        guard let image = renderImage(blocks, scale: scale),
              let rep = image.representations.first as? NSBitmapImageRep else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: - Tree (§5)

    /// Serializes the scene graph to text locally, no inference. Parenthood is
    /// inferred from containment because that is how you actually draw — you put
    /// a box inside a frame, you don't declare a relationship.
    static func tree(_ blocks: [Block]) -> String {
        let visible = blocks.filter { $0.kind != .redact }
        guard !visible.isEmpty else { return "" }

        let roots = visible.filter { parent(of: $0, in: visible) == nil }
        var lines: [String] = []
        var signatures: [UUID: String] = [:]
        for block in visible { signatures[block.id] = signature(block, in: visible) }
        emitSiblings(roots, in: visible, signatures: signatures, depth: 0, into: &lines)
        return lines.joined(separator: "\n")
    }

    /// Six identical rows should serialize as one line with a count, not six
    /// lines — that repetition is most of the gap between the tree and the
    /// ~120-token target in §5.
    private static func emitSiblings(_ siblings: [Block], in blocks: [Block],
                                     signatures: [UUID: String], depth: Int,
                                     into lines: inout [String]) {
        let list = ordered(siblings)
        var i = 0
        while i < list.count {
            var run = 1
            let sig = signatures[list[i].id]
            while i + run < list.count, signatures[list[i + run].id] == sig { run += 1 }
            let group = Array(list[i..<(i + run)])
            emit(list[i], in: blocks, signatures: signatures, depth: depth,
                 repeatCount: run, groupBounds: group.map { $0.rect.standardized }
                    .reduce(CGRect.null) { $0.union($1) },
                 into: &lines)
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
        return "\(block.kind.rawValue):\(Int(r.width))x\(Int(r.height)):\(block.text):\(block.colorIndex):[\(childSignature)]"
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
                             depth: Int, repeatCount: Int, groupBounds: CGRect,
                             into lines: inout [String]) {
        let indent = String(repeating: "  ", count: depth)
        let r = block.rect.standardized
        var parts: [String] = []

        switch block.kind {
        case .frame:
            parts.append("Frame \(Int(r.width))x\(Int(r.height))")
        case .text:
            parts.append("Text")
        case .box:
            parts.append("Box \(Int(r.width))x\(Int(r.height))")
        default:
            parts.append(block.kind.label)
        }

        if repeatCount > 1 { parts.append("×\(repeatCount)") }

        // A collapsed run is anchored by the whole run, not by its first member,
        // or a stack of rows would claim to be at the top of its parent.
        if block.kind != .frame, let anchor = anchor(of: groupBounds, in: block, blocks: blocks) {
            parts.append(anchor)
        }
        if !block.text.isEmpty { parts.append("\"\(block.text)\"") }
        if block.colorIndex != 0 {
            parts.append("[\(Palette.name(block.colorIndex).lowercased())]")
        }

        lines.append(indent + parts.joined(separator: "  "))

        let children = blocks.filter { parent(of: $0, in: blocks)?.id == block.id }
        emitSiblings(children, in: blocks, signatures: signatures, depth: depth + 1, into: &lines)
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
    static func copyToPasteboard(_ blocks: [Block], mode: PayloadMode) -> String {
        let pb = NSPasteboard.general
        pb.clearContents()

        guard !blocks.isEmpty else { return "Nothing to copy" }

        // One item carrying both representations lets the receiving app pick the
        // richest form it supports — editors take the image, terminals the text.
        let item = NSPasteboardItem()
        let text = tree(blocks)

        switch mode {
        case .tree:
            item.setString(text, forType: .string)
        case .image:
            guard let png = renderPNGData(blocks) else { return "Nothing to copy" }
            item.setData(png, forType: .png)
        case .treeAndImage:
            item.setString(text, forType: .string)
            if let png = renderPNGData(blocks) { item.setData(png, forType: .png) }
        }

        pb.writeObjects([item])

        switch mode {
        case .tree: return "Copied tree · \(text.split(separator: "\n").count) lines"
        case .image: return "Copied image"
        case .treeAndImage: return "Copied tree + image"
        }
    }
}
