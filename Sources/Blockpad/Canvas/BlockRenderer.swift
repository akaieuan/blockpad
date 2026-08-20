import AppKit
import CoreGraphics

/// Draws the scene. Shared by the on-screen canvas and the PNG exporter so what
/// you send is exactly what you drew.
enum BlockRenderer {

    static func canvasFont(size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont {
        if let rounded = NSFont.systemFont(ofSize: size, weight: weight)
            .fontDescriptor.withDesign(.rounded)
            .flatMap({ NSFont(descriptor: $0, size: size) }) {
            return rounded
        }
        return NSFont.systemFont(ofSize: size, weight: weight)
    }

    static func fontSize(forStroke index: Int) -> CGFloat {
        switch index {
        case 0: return 13
        case 2: return 22
        default: return 16
        }
    }

    static func measure(_ text: String, strokeIndex: Int) -> CGSize {
        let font = canvasFont(size: fontSize(forStroke: strokeIndex))
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: 4000, height: 4000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attrs)
        return CGSize(width: max(24, ceil(bounds.width) + 4), height: max(font.pointSize * 1.35, ceil(bounds.height)))
    }

    // MARK: - Scene

    /// Draws the paper and dot grid in *document* space for the given visible rect.
    static func drawBackground(in ctx: CGContext, visibleDocRect: CGRect, zoom: CGFloat) {
        ctx.setFillColor(Palette.paper.cgColor)
        ctx.fill(visibleDocRect)

        // Grid disappears when zoomed out or it turns into grey mush.
        guard zoom > 0.6 else { return }
        let spacing: CGFloat = 8
        let dot: CGFloat = 1 / zoom
        ctx.setFillColor(Palette.grid.cgColor)
        var y = (visibleDocRect.minY / spacing).rounded(.down) * spacing
        while y < visibleDocRect.maxY {
            var x = (visibleDocRect.minX / spacing).rounded(.down) * spacing
            while x < visibleDocRect.maxX {
                ctx.fill(CGRect(x: x, y: y, width: dot, height: dot))
                x += spacing
            }
            y += spacing
        }
    }

    static func draw(_ block: Block, in ctx: CGContext, zoom: CGFloat) {
        switch block.kind {
        case .frame:   drawFrame(block, in: ctx, zoom: zoom)
        case .box:     drawBox(block, in: ctx, zoom: zoom)
        case .text:    drawText(block, in: ctx)
        case .redact:  drawRedact(block, in: ctx)
        case .arrow:   drawArrow(block, in: ctx)
        case .callout: drawBox(block, in: ctx, zoom: zoom)
        case .pen:     drawPen(block, in: ctx)
        }
    }

    // MARK: - Kinds

    /// Frames cast a soft drop shadow so they read as sheets on a desk (§4).
    private static func drawFrame(_ block: Block, in ctx: CGContext, zoom: CGFloat) {
        let r = block.rect.standardized
        guard r.width > 1, r.height > 1 else { return }

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 3),
                      blur: 14,
                      color: NSColor.black.withAlphaComponent(0.13).cgColor)
        ctx.setFillColor(Palette.sheet.cgColor)
        ctx.fill(r)
        ctx.restoreGState()

        var rough = Rough(seed: block.seed, roughness: 0.7)
        let path = rough.rectangle(r)
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setStrokeColor(NSColor(srgbRed: 0.169, green: 0.165, blue: 0.157, alpha: 0.30).cgColor)
        ctx.setLineWidth(1.0)
        ctx.setLineCap(.round)
        ctx.strokePath()
        ctx.restoreGState()

        // Label sits above the sheet, like an artboard name.
        let name = block.text.isEmpty ? "\(Int(r.width))×\(Int(r.height))" : block.text
        let font = canvasFont(size: 11, weight: .semibold)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor(srgbRed: 0.169, green: 0.165, blue: 0.157, alpha: 0.45)
        ]
        drawString(name, at: CGPoint(x: r.minX + 1, y: r.minY - font.pointSize - 6), attrs: attrs, in: ctx)
    }

    private static func drawBox(_ block: Block, in ctx: CGContext, zoom: CGFloat) {
        let r = block.rect.standardized
        guard r.width > 1, r.height > 1 else { return }
        let color = Palette.color(block.colorIndex)

        var rough = Rough(seed: block.seed)
        let path = rough.rectangle(r)

        ctx.saveGState()
        ctx.addPath(path)
        ctx.setFillColor(color.withAlphaComponent(0.05).cgColor)
        ctx.fillPath(using: .winding)
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(path)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(StrokeWeight.width(block.strokeIndex))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()

        guard !block.text.isEmpty else { return }
        let font = canvasFont(size: fontSize(forStroke: block.strokeIndex))
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingTail
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: para
        ]
        let size = measure(block.text, strokeIndex: block.strokeIndex)
        let box = CGRect(x: r.minX + 4,
                         y: r.midY - size.height / 2,
                         width: max(1, r.width - 8),
                         height: size.height)
        drawString(block.text, in: box, attrs: attrs, in: ctx)
    }

    private static func drawText(_ block: Block, in ctx: CGContext) {
        guard !block.text.isEmpty else { return }
        let color = Palette.color(block.colorIndex)
        let font = canvasFont(size: fontSize(forStroke: block.strokeIndex))
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        drawString(block.text, in: block.rect.standardized, attrs: attrs, in: ctx)
    }

    private static func drawRedact(_ block: Block, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setFillColor(NSColor(srgbRed: 0.169, green: 0.165, blue: 0.157, alpha: 0.92).cgColor)
        ctx.fill(block.rect.standardized)
        ctx.restoreGState()
    }

    private static func drawArrow(_ block: Block, in ctx: CGContext) {
        let r = block.rect
        let p1 = CGPoint(x: r.minX, y: r.minY)
        let p2 = CGPoint(x: r.maxX, y: r.maxY)
        let color = Palette.color(block.colorIndex)
        var rough = Rough(seed: block.seed)
        let path = rough.lineSegment(p1, p2)

        ctx.saveGState()
        ctx.addPath(path)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(StrokeWeight.width(block.strokeIndex))
        ctx.setLineCap(.round)
        ctx.strokePath()

        let angle = atan2(p2.y - p1.y, p2.x - p1.x)
        let headLen: CGFloat = 12 + StrokeWeight.width(block.strokeIndex) * 2
        let head = CGMutablePath()
        for delta in [CGFloat.pi * 0.82, -CGFloat.pi * 0.82] {
            head.move(to: p2)
            head.addLine(to: CGPoint(x: p2.x + cos(angle + delta) * headLen,
                                     y: p2.y + sin(angle + delta) * headLen))
        }
        ctx.addPath(head)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawPen(_ block: Block, in ctx: CGContext) {
        guard block.points.count > 1 else { return }
        let color = Palette.color(block.colorIndex)
        let path = CGMutablePath()
        path.move(to: block.points[0])
        for i in 1..<block.points.count {
            let mid = CGPoint(x: (block.points[i - 1].x + block.points[i].x) / 2,
                              y: (block.points[i - 1].y + block.points[i].y) / 2)
            path.addQuadCurve(to: mid, control: block.points[i - 1])
        }
        ctx.saveGState()
        ctx.addPath(path)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(StrokeWeight.width(block.strokeIndex))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Text helpers

    /// AppKit string drawing needs a current NSGraphicsContext, and the canvas
    /// view is flipped, so wrap both here rather than at every call site.
    private static func drawString(_ s: String, at point: CGPoint, attrs: [NSAttributedString.Key: Any], in ctx: CGContext) {
        withFlippedContext(ctx) {
            (s as NSString).draw(at: point, withAttributes: attrs)
        }
    }

    private static func drawString(_ s: String, in rect: CGRect, attrs: [NSAttributedString.Key: Any], in ctx: CGContext) {
        withFlippedContext(ctx) {
            (s as NSString).draw(with: rect,
                                 options: [.usesLineFragmentOrigin, .usesFontLeading],
                                 attributes: attrs)
        }
    }

    private static func withFlippedContext(_ ctx: CGContext, _ body: () -> Void) {
        let previous = NSGraphicsContext.current
        let gc = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.current = gc
        body()
        NSGraphicsContext.current = previous
    }
}
