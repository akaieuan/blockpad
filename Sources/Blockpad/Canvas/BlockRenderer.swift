import AppKit
import BlockpadKit
import CoreGraphics

/// Crisp by default, sketchy on request.
///
/// §4 argued roughness signals provisional, and that a crisp rectangle invites
/// the model to treat proportions as exact. That risk is covered elsewhere now:
/// the tree carries exact coordinates and counts, so precision is stated rather
/// than inferred from the picture. The sketch renderer stays behind a toggle.
struct RenderOptions {
    var theme: CanvasTheme = .paper
    var sketchy: Bool = false
}

enum BlockRenderer {

    static let cornerRadius: CGFloat = 10

    /// SF Pro, not rounded: rounded reads friendly-informal, which fights the
    /// crisp direction.
    static func canvasFont(size: CGFloat, weight: NSFont.Weight = .regular) -> NSFont {
        NSFont.systemFont(ofSize: size, weight: weight)
    }

    /// Text scales with stroke weight, so a bold outline carries bold-ish text
    /// without a separate control.
    static func fontSize(forStrokeWidth width: Double) -> CGFloat {
        switch width {
        case ..<1.4: return 13
        case ..<2.6: return 15
        case ..<4: return 18
        default: return 21
        }
    }

    /// Radius is clamped so a big number on a small box cannot invert the shape.
    static func effectiveRadius(_ block: Block, rect r: CGRect) -> CGFloat {
        max(0, min(CGFloat(block.cornerRadius), min(r.width, r.height) / 2))
    }

    static func measure(_ text: String, strokeWidth: Double) -> CGSize {
        let font = canvasFont(size: fontSize(forStrokeWidth: strokeWidth))
        let bounds = (text as NSString).boundingRect(
            with: CGSize(width: 4000, height: 4000),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font])
        return CGSize(width: max(24, ceil(bounds.width) + 4),
                      height: max(font.pointSize * 1.35, ceil(bounds.height)))
    }

    // MARK: - Background

    static func drawBackground(in ctx: CGContext, visibleDocRect: CGRect, zoom: CGFloat, theme: CanvasTheme) {
        ctx.setFillColor(theme.color.cgColor)
        ctx.fill(visibleDocRect)

        guard zoom > 0.6 else { return }
        let spacing: CGFloat = 8
        let dot: CGFloat = 1 / zoom
        ctx.setFillColor(theme.gridColor.cgColor)
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

    // MARK: - Blocks

    static func draw(_ block: Block, in ctx: CGContext, zoom: CGFloat, options: RenderOptions) {
        ctx.saveGState()
        if block.opacity < 1 {
            ctx.setAlpha(CGFloat(block.opacity))
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        }

        switch block.kind {
        case .frame:  drawFrame(block, in: ctx, options: options)
        case .text:   drawText(block, in: ctx, options: options)
        case .redact: drawRedact(block, in: ctx)
        case .arrow, .line: drawLinear(block, in: ctx, options: options)
        case .pen:    drawPen(block, in: ctx, options: options)
        case .box, .ellipse, .diamond: drawShape(block, in: ctx, options: options)
        }

        if block.opacity < 1 { ctx.endTransparencyLayer() }
        ctx.restoreGState()
    }

    /// Frames cast a soft drop shadow so they read as sheets on a desk (§4).
    private static func drawFrame(_ block: Block, in ctx: CGContext, options: RenderOptions) {
        let r = block.rect.standardized
        guard r.width > 1, r.height > 1 else { return }
        let theme = options.theme

        ctx.saveGState()
        if !theme.isDark {
            ctx.setShadow(offset: CGSize(width: 0, height: 4), blur: 18,
                          color: NSColor.black.withAlphaComponent(0.12).cgColor)
        }
        ctx.setFillColor(theme.sheetColor.cgColor)
        ctx.fill(r)
        ctx.restoreGState()

        ctx.saveGState()
        if options.sketchy {
            var rough = Rough(seed: block.seed, roughness: 0.7)
            ctx.addPath(rough.rectangle(r))
        } else {
            ctx.addPath(CGPath(rect: r, transform: nil))
        }
        ctx.setStrokeColor(theme.frameStroke.cgColor)
        ctx.setLineWidth(1.0)
        ctx.strokePath()
        ctx.restoreGState()

        let name = block.text.isEmpty ? "\(Int(r.width))×\(Int(r.height))" : block.text
        let font = canvasFont(size: 11, weight: .medium)
        drawString(name, at: CGPoint(x: r.minX + 1, y: r.minY - font.pointSize - 7),
                   attrs: [.font: font, .foregroundColor: theme.frameStroke], in: ctx)
    }

    private static func drawShape(_ block: Block, in ctx: CGContext, options: RenderOptions) {
        let r = block.rect.standardized
        guard r.width > 1, r.height > 1 else { return }
        let color = options.theme.inkAdjusted(Palette.color(block.stroke))

        var rough = Rough(seed: block.seed)
        let strokePath: CGPath
        if options.sketchy {
            switch block.kind {
            case .ellipse: strokePath = rough.ellipse(r)
            case .diamond: strokePath = rough.diamond(r)
            default:
                let radius = effectiveRadius(block, rect: r)
                strokePath = radius > 0.5
                    ? rough.roundedRectangle(r, radius: radius)
                    : rough.rectangle(r)
            }
        } else {
            strokePath = smoothPath(for: block, rect: r)
        }

        drawFill(block, in: ctx, rect: r, rough: &rough, options: options)

        ctx.saveGState()
        ctx.addPath(strokePath)
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(CGFloat(block.strokeWidth))
        ctx.setLineCap(options.sketchy ? .round : .butt)
        ctx.setLineJoin(options.sketchy ? .round : .miter)
        ctx.strokePath()
        ctx.restoreGState()

        guard !block.text.isEmpty else { return }
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.lineBreakMode = .byTruncatingTail
        let size = measure(block.text, strokeWidth: block.strokeWidth)
        drawString(block.text,
                   in: CGRect(x: r.minX + 6, y: r.midY - size.height / 2,
                              width: max(1, r.width - 12), height: size.height),
                   attrs: [.font: canvasFont(size: fontSize(forStrokeWidth: block.strokeWidth)),
                           .foregroundColor: color, .paragraphStyle: para],
                   in: ctx)
    }

    /// Fill is clipped to the smooth shape even in sketch mode: clipping to the
    /// rough path leaks, because its double-stroke subpaths overlap and the
    /// winding rule punches holes.
    private static func drawFill(_ block: Block, in ctx: CGContext, rect r: CGRect,
                                 rough: inout Rough, options: RenderOptions) {
        guard block.fillStyle != .none, let hex = block.fill else { return }
        let fill = Palette.color(hex)

        ctx.saveGState()
        ctx.addPath(smoothPath(for: block, rect: r))
        ctx.clip()

        switch block.fillStyle {
        case .solid:
            ctx.setFillColor(fill.cgColor)
            ctx.fill(r)
        case .hachure:
            let gap = 7 + CGFloat(block.strokeWidth) * 1.5
            if options.sketchy {
                ctx.addPath(rough.hachure(r, gap: gap))
            } else {
                let path = CGMutablePath()
                var x = r.minX - r.height
                while x < r.maxX + r.height {
                    path.move(to: CGPoint(x: x, y: r.minY))
                    path.addLine(to: CGPoint(x: x + r.height, y: r.maxY))
                    x += gap
                }
                ctx.addPath(path)
            }
            ctx.setStrokeColor(fill.blended(withFraction: 0.18, of: .black)?.cgColor ?? fill.cgColor)
            ctx.setLineWidth(max(1.2, CGFloat(block.strokeWidth) * 0.75))
            ctx.strokePath()
        case .none:
            break
        }
        ctx.restoreGState()
    }

    static func smoothPath(for block: Block, rect r: CGRect) -> CGPath {
        switch block.kind {
        case .ellipse:
            return CGPath(ellipseIn: r, transform: nil)
        case .diamond:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: r.midX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.midY))
            p.closeSubpath()
            return p
        default:
            let radius = effectiveRadius(block, rect: r)
            return radius > 0.5
                ? CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
                : CGPath(rect: r, transform: nil)
        }
    }

    private static func drawText(_ block: Block, in ctx: CGContext, options: RenderOptions) {
        guard !block.text.isEmpty else { return }
        let color = options.theme.inkAdjusted(Palette.color(block.stroke))
        drawString(block.text, in: block.rect.standardized,
                   attrs: [.font: canvasFont(size: fontSize(forStrokeWidth: block.strokeWidth)),
                           .foregroundColor: color],
                   in: ctx)
    }

    private static func drawRedact(_ block: Block, in ctx: CGContext) {
        ctx.saveGState()
        ctx.setFillColor(NSColor(srgbRed: 0.169, green: 0.165, blue: 0.157, alpha: 0.92).cgColor)
        ctx.fill(block.rect.standardized)
        ctx.restoreGState()
    }

    /// Arrows and lines run corner to corner of their (unstandardized) rect, so
    /// the drag direction is preserved and the head lands where you released.
    private static func drawLinear(_ block: Block, in ctx: CGContext, options: RenderOptions) {
        let p1 = block.rect.origin
        let p2 = CGPoint(x: block.rect.maxX, y: block.rect.maxY)
        guard hypot(p2.x - p1.x, p2.y - p1.y) > 1 else { return }
        let color = options.theme.inkAdjusted(Palette.color(block.stroke))

        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(CGFloat(block.strokeWidth))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        if options.sketchy {
            var rough = Rough(seed: block.seed)
            ctx.addPath(rough.lineSegment(p1, p2))
        } else {
            let path = CGMutablePath()
            path.move(to: p1)
            path.addLine(to: p2)
            ctx.addPath(path)
        }
        ctx.strokePath()

        if block.kind == .arrow {
            let angle = atan2(p2.y - p1.y, p2.x - p1.x)
            let headLength = 10 + CGFloat(block.strokeWidth) * 2.2
            let head = CGMutablePath()
            for spread in [CGFloat.pi * 0.85, -CGFloat.pi * 0.85] {
                head.move(to: p2)
                head.addLine(to: CGPoint(x: p2.x + cos(angle + spread) * headLength,
                                         y: p2.y + sin(angle + spread) * headLength))
            }
            ctx.addPath(head)
            ctx.strokePath()
        }
        ctx.restoreGState()
    }

    private static func drawPen(_ block: Block, in ctx: CGContext, options: RenderOptions) {
        guard block.points.count > 1 else { return }
        let color = options.theme.inkAdjusted(Palette.color(block.stroke))
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
        ctx.setLineWidth(CGFloat(block.strokeWidth))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Text helpers

    /// AppKit string drawing needs a current NSGraphicsContext, and the canvas
    /// is flipped, so wrap both here rather than at every call site.
    private static func drawString(_ s: String, at point: CGPoint, attrs: [NSAttributedString.Key: Any], in ctx: CGContext) {
        withFlippedContext(ctx) { (s as NSString).draw(at: point, withAttributes: attrs) }
    }

    private static func drawString(_ s: String, in rect: CGRect, attrs: [NSAttributedString.Key: Any], in ctx: CGContext) {
        withFlippedContext(ctx) {
            (s as NSString).draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
        }
    }

    private static func withFlippedContext(_ ctx: CGContext, _ body: () -> Void) {
        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        body()
        NSGraphicsContext.current = previous
    }
}
