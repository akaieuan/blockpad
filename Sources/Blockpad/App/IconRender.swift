import AppKit
import CoreGraphics

/// Draws the app icon: a white squircle holding a miniature blockout.
///
/// The mark is the operation. Three coloured blocks in a left/right split are
/// the most common thing anyone actually draws here, and at 16pt it still reads
/// as "a layout" rather than as a generic document.
enum IconRender {

    /// Sizes macOS wants in an .iconset.
    private static let variants: [(name: String, pixels: Int)] = [
        ("icon_16x16", 16), ("icon_16x16@2x", 32),
        ("icon_32x32", 32), ("icon_32x32@2x", 64),
        ("icon_128x128", 128), ("icon_128x128@2x", 256),
        ("icon_256x256", 256), ("icon_256x256@2x", 512),
        ("icon_512x512", 512), ("icon_512x512@2x", 1024)
    ]

    static func run(outputDirectory: String) {
        let dir = URL(fileURLWithPath: outputDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for variant in variants {
            guard let data = png(size: variant.pixels) else {
                print("failed \(variant.name)")
                continue
            }
            try? data.write(to: dir.appendingPathComponent("\(variant.name).png"))
        }
        print("wrote \(variants.count) icon sizes to \(dir.path)")
    }

    static func png(size: Int) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { return nil }

        draw(in: ctx, size: CGFloat(size))
        return rep.representation(using: .png, properties: [:])
    }

    static func draw(in ctx: CGContext, size s: CGFloat) {
        ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

        // macOS icons sit inset in their canvas rather than bleeding to the edge.
        let inset = s * 0.094
        let card = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
        // Apple's continuous-corner ratio for app icons.
        let radius = card.width * 0.2237
        let squircle = CGPath(roundedRect: card, cornerWidth: radius, cornerHeight: radius, transform: nil)

        // Shadow is skipped on the tiny sizes, where it only muddies the shape.
        if s >= 64 {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.035,
                          color: NSColor.black.withAlphaComponent(0.22).cgColor)
            ctx.addPath(squircle)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        } else {
            ctx.addPath(squircle)
            ctx.setFillColor(NSColor.white.cgColor)
            ctx.fillPath()
        }

        // Hairline keeps the white card from vanishing on a white background.
        if s >= 128 {
            ctx.addPath(squircle)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.07).cgColor)
            ctx.setLineWidth(max(1, s * 0.004))
            ctx.strokePath()
        }

        ctx.saveGState()
        ctx.addPath(squircle)
        ctx.clip()

        // Content in unit space, then scaled — keeps every size identical.
        let pad = card.width * 0.175
        let content = card.insetBy(dx: pad, dy: pad)
        let gap = content.width * 0.075
        let leftWidth = content.width * 0.44
        let rightX = content.minX + leftWidth + gap
        let rightWidth = content.maxX - rightX
        let rowHeight = (content.height - gap) / 2
        let blockRadius = content.width * (s >= 64 ? 0.055 : 0.03)

        let blocks: [(CGRect, NSColor)] = [
            (CGRect(x: content.minX, y: content.minY, width: leftWidth, height: content.height),
             Palette.color(1)),
            (CGRect(x: rightX, y: content.minY, width: rightWidth, height: rowHeight),
             Palette.color(4)),
            (CGRect(x: rightX, y: content.minY + rowHeight + gap, width: rightWidth, height: rowHeight),
             Palette.color(2))
        ]

        for (rect, color) in blocks {
            let path = CGPath(roundedRect: rect, cornerWidth: blockRadius,
                              cornerHeight: blockRadius, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(color.cgColor)
            ctx.fillPath()
        }

        ctx.restoreGState()
    }
}
