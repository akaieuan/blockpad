import AppKit
import CoreGraphics

/// Draws the app icon: a pad of blocks, in isometric, on a card.
///
/// The mark is the name. Three slabs stacked with an orange one on top read as
/// a *pad of blocks* — a physical thing you take the top sheet off — where the
/// old mark's flat rectangles only ever read as "a layout". Everything is
/// expressed in units of the card width, so every size is the same drawing.
enum IconRender {

    // MARK: - Brand

    /// The one saturated colour in the mark. It is the same in both schemes —
    /// the orange is the brand, the ink is only ever contrast.
    static let orange = NSColor(srgbRed: 0.976, green: 0.451, blue: 0.086, alpha: 1)  // #F97316

    /// Light and dark are not the same drawing recoloured slightly: the two ink
    /// slabs invert with the card. Dark slabs on a black card are black on
    /// black, and the stack — which is the entire idea — disappears.
    enum Scheme: String, CaseIterable {
        case light, dark

        var card: NSColor {
            switch self {
            case .light: return NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)              // #FFFFFF
            case .dark:  return NSColor(srgbRed: 0.055, green: 0.055, blue: 0.063, alpha: 1)  // #0E0E10
            }
        }

        /// Which way the card's gradient runs, and the strength of it.
        var cardLift: CGFloat { self == .light ? -0.06 : 0.10 }

        /// Bottom then middle slab, darkest first in reading order.
        var slabs: [NSColor] {
            switch self {
            case .light:
                return [NSColor(srgbRed: 0.098, green: 0.098, blue: 0.118, alpha: 1),  // #19191E
                        NSColor(srgbRed: 0.208, green: 0.208, blue: 0.239, alpha: 1)]  // #35353D
            case .dark:
                return [NSColor(srgbRed: 0.408, green: 0.408, blue: 0.447, alpha: 1),  // #686872
                        NSColor(srgbRed: 0.612, green: 0.612, blue: 0.655, alpha: 1)]  // #9C9CA7
            }
        }

        var contactOpacity: CGFloat { self == .light ? 0.20 : 0.60 }
        var cardShadowOpacity: CGFloat { self == .light ? 0.22 : 0.45 }
        /// A white card needs a hairline or it vanishes on a white page.
        var needsHairline: Bool { self == .light }
    }

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
            guard let data = png(size: variant.pixels, scheme: .dark) else {
                print("failed \(variant.name)")
                continue
            }
            try? data.write(to: dir.appendingPathComponent("\(variant.name).png"))
        }
        print("wrote \(variants.count) icon sizes to \(dir.path)")
    }

    /// Oversized masters for the website and press use, plus the vector. Kept
    /// out of the .iconset, which rejects any filename outside Apple's fixed set.
    static func runLogo(outputDirectory: String) {
        let dir = URL(fileURLWithPath: outputDirectory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for scheme in Scheme.allCases {
            for size in [512, 1024, 2048] {
                guard let data = png(size: size, scheme: scheme) else { continue }
                try? data.write(to: dir.appendingPathComponent("logo-\(scheme.rawValue)-\(size).png"))
            }
            try? svg(scheme: scheme).data(using: .utf8)?
                .write(to: dir.appendingPathComponent("logo-\(scheme.rawValue).svg"))
        }
        print("wrote logo masters for \(Scheme.allCases.count) schemes to \(dir.path)")
    }

    // MARK: - Geometry

    /// The card, inset the way macOS icons are rather than bleeding to the edge.
    static func cardRect(_ s: CGFloat) -> CGRect {
        let inset = s * 0.094
        return CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    }

    /// Apple's continuous-corner ratio for app icons.
    static func cardRadius(_ card: CGRect) -> CGFloat { card.width * 0.2237 }

    /// Isometric projection into a y-up context. Depth recedes *downward* on
    /// screen; getting that sign wrong turns every box into a bowtie.
    private static func iso(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint {
        CGPoint(x: (x - y) * 0.8660254, y: -(x + y) * 0.5 + z)
    }

    /// One slab, as its three visible faces. Returned in paint order.
    ///
    /// Shared by the raster and vector paths so the two cannot drift: the SVG is
    /// the same polygons with the y axis flipped.
    static func slabFaces(origin: CGPoint, unit u: CGFloat,
                          width w: CGFloat, depth d: CGFloat, height h: CGFloat)
        -> [(points: [CGPoint], shade: CGFloat)] {
        func p(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint {
            let q = iso(x * u, y * u, z * u)
            return CGPoint(x: origin.x + q.x, y: origin.y + q.y)
        }
        return [
            // Right face catches more light than the left; the top is brightest,
            // which is what makes it read as a solid and not a flat hexagon.
            ([p(w, 0, 0), p(w, d, 0), p(w, d, h), p(w, 0, h)], -0.30),
            ([p(0, d, 0), p(w, d, 0), p(w, d, h), p(0, d, h)], -0.55),
            ([p(0, 0, h), p(w, 0, h), p(w, d, h), p(0, d, h)], 0.10)
        ]
    }

    /// The three slabs, bottom to top: two inks under one orange.
    static func stack(in card: CGRect, scheme: Scheme)
        -> (unit: CGFloat, base: CGPoint, colors: [NSColor]) {
        (card.width * 0.165,
         CGPoint(x: card.midX, y: card.minY + card.height * 0.36),
         scheme.slabs + [orange])
    }

    /// Vertical rise between slabs, in units.
    static let slabLift: CGFloat = 0.62
    static let slabHeight: CGFloat = 0.55
    static let slabSpan: CGFloat = 2

    // MARK: - Raster

    static func png(size: Int, scheme: Scheme = .dark) -> Data? {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep)?.cgContext else { return nil }

        draw(in: ctx, size: CGFloat(size), scheme: scheme)
        return rep.representation(using: .png, properties: [:])
    }

    static func draw(in ctx: CGContext, size s: CGFloat, scheme: Scheme = .dark) {
        ctx.clear(CGRect(x: 0, y: 0, width: s, height: s))

        let card = cardRect(s)
        let radius = cardRadius(card)
        let squircle = CGPath(roundedRect: card, cornerWidth: radius,
                              cornerHeight: radius, transform: nil)

        // Shadow is skipped on the tiny sizes, where it only muddies the shape.
        if s >= 64 {
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.018), blur: s * 0.05,
                          color: NSColor.black.withAlphaComponent(scheme.cardShadowOpacity).cgColor)
            ctx.addPath(squircle)
            ctx.setFillColor(scheme.card.cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        } else {
            ctx.addPath(squircle)
            ctx.setFillColor(scheme.card.cgColor)
            ctx.fillPath()
        }

        // Hairline keeps a white card from vanishing on a white page.
        if scheme.needsHairline, s >= 128 {
            ctx.addPath(squircle)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.08).cgColor)
            ctx.setLineWidth(max(1, s * 0.004))
            ctx.strokePath()
        }

        ctx.saveGState()
        ctx.addPath(squircle)
        ctx.clip()

        // Glass: one soft top-down gradient across the card itself. Subtle
        // enough that it never competes with the mark.
        if s >= 64 {
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [lighten(scheme.card, scheme.cardLift).cgColor,
                         scheme.card.cgColor] as CFArray,
                locations: [0, 1])!
            ctx.drawLinearGradient(gradient,
                                   start: CGPoint(x: card.midX, y: card.maxY),
                                   end: CGPoint(x: card.midX, y: card.minY),
                                   options: [])
        }

        let (unit, base, colors) = stack(in: card, scheme: scheme)

        // Contact shadow under the bottom slab.
        if s >= 128 {
            ctx.saveGState()
            ctx.translateBy(x: card.midX, y: base.y - unit * 1.05)
            ctx.scaleBy(x: 1, y: 0.30)
            ctx.setShadow(offset: .zero, blur: s * 0.06,
                          color: NSColor.black.withAlphaComponent(scheme.contactOpacity + 0.05).cgColor)
            ctx.setFillColor(NSColor.black.withAlphaComponent(scheme.contactOpacity).cgColor)
            let r = card.width * 0.33
            ctx.fillEllipse(in: CGRect(x: -r, y: -r, width: r * 2, height: r * 2))
            ctx.restoreGState()
        }

        for (index, color) in colors.enumerated() {
            let origin = CGPoint(x: base.x, y: base.y + CGFloat(index) * unit * slabLift)
            for face in slabFaces(origin: origin, unit: unit,
                                  width: slabSpan, depth: slabSpan, height: slabHeight) {
                ctx.beginPath()
                ctx.move(to: face.points[0])
                for point in face.points.dropFirst() { ctx.addLine(to: point) }
                ctx.closePath()
                ctx.setFillColor(lighten(color, face.shade).cgColor)
                ctx.fillPath()
            }
        }

        ctx.restoreGState()
    }

    /// Positive lightens toward white, negative multiplies toward black.
    static func lighten(_ color: NSColor, _ amount: CGFloat) -> NSColor {
        guard let c = color.usingColorSpace(.sRGB) else { return color }
        if amount >= 0 {
            return NSColor(srgbRed: c.redComponent + (1 - c.redComponent) * amount,
                           green: c.greenComponent + (1 - c.greenComponent) * amount,
                           blue: c.blueComponent + (1 - c.blueComponent) * amount,
                           alpha: c.alphaComponent)
        }
        let k = 1 + amount
        return NSColor(srgbRed: c.redComponent * k, green: c.greenComponent * k,
                       blue: c.blueComponent * k, alpha: c.alphaComponent)
    }

    // MARK: - Vector

    /// Vector master, generated from the same geometry as `draw`. SVG's y axis
    /// runs downward, so every point is mirrored on the way out — the shapes
    /// themselves are not restated.
    static func svg(scheme: Scheme = .dark) -> String {
        let s: CGFloat = 1024
        let card = cardRect(s)
        let radius = cardRadius(card)
        let (unit, base, colors) = stack(in: card, scheme: scheme)

        func hex(_ color: NSColor) -> String {
            guard let rgb = color.usingColorSpace(.sRGB) else { return "#000000" }
            return String(format: "#%02X%02X%02X",
                          Int((rgb.redComponent * 255).rounded()),
                          Int((rgb.greenComponent * 255).rounded()),
                          Int((rgb.blueComponent * 255).rounded()))
        }

        var polygons: [String] = []
        for (index, color) in colors.enumerated() {
            let origin = CGPoint(x: base.x, y: base.y + CGFloat(index) * unit * slabLift)
            for face in slabFaces(origin: origin, unit: unit,
                                  width: slabSpan, depth: slabSpan, height: slabHeight) {
                let points = face.points
                    .map { String(format: "%.2f,%.2f", $0.x, s - $0.y) }
                    .joined(separator: " ")
                polygons.append("  <polygon points=\"\(points)\" fill=\"\(hex(lighten(color, face.shade)))\"/>")
            }
        }

        let shadowY = s - (base.y - unit * 1.05)

        return """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
          <title>Blockpad</title>
          <defs>
            <linearGradient id="card" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stop-color="\(hex(lighten(scheme.card, scheme.cardLift)))"/>
              <stop offset="1" stop-color="\(hex(scheme.card))"/>
            </linearGradient>
            <radialGradient id="contact">
              <stop offset="0" stop-color="#000000" stop-opacity="\(fmt(scheme.contactOpacity))"/>
              <stop offset="1" stop-color="#000000" stop-opacity="0"/>
            </radialGradient>
            <clipPath id="cardClip">
              <rect x="\(fmt(card.minX))" y="\(fmt(card.minY))" width="\(fmt(card.width))" \
        height="\(fmt(card.height))" rx="\(fmt(radius))" ry="\(fmt(radius))"/>
            </clipPath>
          </defs>
          <rect x="\(fmt(card.minX))" y="\(fmt(card.minY))" width="\(fmt(card.width))" \
        height="\(fmt(card.height))" rx="\(fmt(radius))" ry="\(fmt(radius))" fill="url(#card)"/>
          <g clip-path="url(#cardClip)">
            <ellipse cx="\(fmt(card.midX))" cy="\(fmt(shadowY))" rx="\(fmt(card.width * 0.33))" \
        ry="\(fmt(card.width * 0.33 * 0.30))" fill="url(#contact)"/>
        \(polygons.joined(separator: "\n"))
          </g>
        </svg>
        """
    }

    private static func fmt(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }
}
