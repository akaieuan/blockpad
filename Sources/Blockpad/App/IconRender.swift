import AppKit
import CoreGraphics

/// Draws the app icon: a cube held open along its own seams.
///
/// The mark is a single isometric cube whose three faces are pushed apart along
/// their normals, with the cube's three interior edges left drawn as hairlines
/// in the gaps. So it reads two ways at once — a block, and blocks connected by
/// lines — which is the product. The faces are flat: three tones and no
/// gradients, because the geometry already carries the depth and shading it
/// would only make it look rendered.
///
/// Everything is expressed in units of the card width, so every size is the
/// same drawing rather than a set of drawings that drift.
enum IconRender {

    // MARK: - Brand

    /// The one saturated colour in the mark, identical in both schemes. The
    /// orange is the brand; the ink is only ever contrast.
    static let orange = NSColor(srgbRed: 0.976, green: 0.451, blue: 0.086, alpha: 1)  // #F97316

    /// Light and dark are not one drawing recoloured. The two ink faces invert
    /// with the card: dark faces on a near-black card are black on black, and
    /// the cube disappears.
    enum Scheme: String, CaseIterable {
        case light, dark

        var card: NSColor {
            switch self {
            case .light: return NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)              // #FFFFFF
            case .dark:  return NSColor(srgbRed: 0.055, green: 0.055, blue: 0.063, alpha: 1)  // #0E0E10
            }
        }

        /// The right face catches more light than the left in both schemes —
        /// that difference is the only thing making a flat hexagon read as a
        /// solid, so it survives the inversion.
        var rightFace: NSColor {
            switch self {
            case .light: return NSColor(srgbRed: 0.176, green: 0.176, blue: 0.204, alpha: 1)  // #2D2D34
            case .dark:  return NSColor(srgbRed: 0.639, green: 0.639, blue: 0.682, alpha: 1)  // #A3A3AE
            }
        }

        var leftFace: NSColor {
            switch self {
            case .light: return NSColor(srgbRed: 0.086, green: 0.086, blue: 0.106, alpha: 1)  // #16161B
            case .dark:  return NSColor(srgbRed: 0.427, green: 0.427, blue: 0.467, alpha: 1)  // #6D6D77
            }
        }

        /// The seams. Hairline weight and well under full contrast, so they read
        /// as structure rather than as a second subject.
        var seam: NSColor {
            switch self {
            case .light: return NSColor(srgbRed: 0.086, green: 0.086, blue: 0.106, alpha: 0.38)
            case .dark:  return NSColor(white: 1, alpha: 0.42)
            }
        }

        /// Which way the card's own gradient runs.
        var cardLift: CGFloat { self == .light ? -0.05 : 0.10 }
        var cardShadowOpacity: CGFloat { self == .light ? 0.22 : 0.45 }
        /// A white card needs a hairline or it vanishes on a white page.
        var needsHairline: Bool { self == .light }
    }

    // MARK: - Proportions

    /// Cube radius, as a fraction of the card width.
    static let cubeRadius: CGFloat = 0.29
    /// How far each face slides along its normal, as a fraction of the radius.
    static let faceGap: CGFloat = 0.22
    /// Seam weight, as a fraction of the card width.
    static let seamWidth: CGFloat = 0.020
    /// How far along the centre-to-vertex span each seam runs. Under 1, so the
    /// seams stop inside the notches between faces and read as connective
    /// tissue. Running them to the vertices — or past — makes them protrude
    /// into the outer corners and the cube stops holding together.
    static let seamReach: CGFloat = 0.55
    /// Below this pixel size the seams would be sub-pixel and the gaps would
    /// read as damage, so the cube is drawn closed and solid instead. Simplify
    /// small rather than render the same thing badly.
    static let detailThreshold: CGFloat = 64

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

    /// Oversized masters for the website and press use, plus the vectors. Kept
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

    /// A face of the exploded cube: the polygon, and which colour role it takes.
    enum FaceRole { case top, right, left }

    /// The whole mark, in one place, so the raster and the vector cannot drift.
    ///
    /// `open` is false at small sizes, which closes the gaps and returns the
    /// three faces of a plain solid cube.
    static func faces(in card: CGRect, open: Bool)
        -> (faces: [(points: [CGPoint], role: FaceRole)], seams: [(CGPoint, CGPoint)]) {
        let r = card.width * cubeRadius
        let gap = open ? r * faceGap : 0
        let k: CGFloat = 0.8660254
        let o = CGPoint(x: card.midX, y: card.midY)

        func v(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint { CGPoint(x: o.x + dx, y: o.y + dy) }
        let top = v(0, r), ur = v(k * r, r / 2), lr = v(k * r, -r / 2)
        let bot = v(0, -r), ll = v(-k * r, -r / 2), ul = v(-k * r, r / 2)

        // Each face travels along the normal of the cube face it stands for.
        let dTop = CGPoint(x: 0, y: gap)
        let dRight = CGPoint(x: k * gap, y: -gap / 2)
        let dLeft = CGPoint(x: -k * gap, y: -gap / 2)

        func moved(_ pts: [CGPoint], _ d: CGPoint) -> [CGPoint] {
            pts.map { CGPoint(x: $0.x + d.x, y: $0.y + d.y) }
        }

        // The cube's three interior edges. Drawn under the faces, so only the
        // part bridging a gap is ever visible.
        let seams = open ? [ur, ul, bot].map { end in
            (o, CGPoint(x: o.x + (end.x - o.x) * seamReach,
                        y: o.y + (end.y - o.y) * seamReach))
        } : []

        return ([
            (moved([ur, lr, bot, o], dRight), .right),
            (moved([ul, o, bot, ll], dLeft), .left),
            (moved([top, ur, o, ul], dTop), .top)
        ], seams)
    }

    static func color(for role: FaceRole, scheme: Scheme) -> NSColor {
        switch role {
        case .top: return orange
        case .right: return scheme.rightFace
        case .left: return scheme.leftFace
        }
    }

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
        if s >= detailThreshold {
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

        ctx.saveGState()
        ctx.addPath(squircle)
        ctx.clip()

        // Glass: one soft top-down gradient across the card. Subtle enough that
        // it never competes with the mark.
        if s >= detailThreshold {
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

        let (faces, seams) = faces(in: card, open: s >= detailThreshold)

        ctx.setStrokeColor(scheme.seam.cgColor)
        ctx.setLineWidth(card.width * seamWidth)
        ctx.setLineCap(.round)
        for (a, b) in seams {
            ctx.beginPath()
            ctx.move(to: a)
            ctx.addLine(to: b)
            ctx.strokePath()
        }

        for face in faces {
            ctx.beginPath()
            ctx.move(to: face.points[0])
            for point in face.points.dropFirst() { ctx.addLine(to: point) }
            ctx.closePath()
            ctx.setFillColor(color(for: face.role, scheme: scheme).cgColor)
            ctx.fillPath()
        }

        ctx.restoreGState()

        // Hairline keeps a white card from vanishing on a white page. Drawn last
        // so the clip does not eat half its width.
        if scheme.needsHairline, s >= 128 {
            ctx.addPath(squircle)
            ctx.setStrokeColor(NSColor.black.withAlphaComponent(0.08).cgColor)
            ctx.setLineWidth(max(1, s * 0.004))
            ctx.strokePath()
        }
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

    /// Vector master, generated from the same `faces` call as the raster. SVG's
    /// y axis runs downward, so every point is mirrored on the way out — the
    /// geometry itself is not restated.
    static func svg(scheme: Scheme = .dark) -> String {
        let s: CGFloat = 1024
        let card = cardRect(s)
        let radius = cardRadius(card)
        let (faces, seams) = faces(in: card, open: true)

        func hex(_ color: NSColor) -> String {
            guard let rgb = color.usingColorSpace(.sRGB) else { return "#000000" }
            return String(format: "#%02X%02X%02X",
                          Int((rgb.redComponent * 255).rounded()),
                          Int((rgb.greenComponent * 255).rounded()),
                          Int((rgb.blueComponent * 255).rounded()))
        }
        func alpha(_ color: NSColor) -> String {
            guard let rgb = color.usingColorSpace(.sRGB) else { return "1" }
            return String(format: "%.2f", rgb.alphaComponent)
        }

        let seamMarkup = seams.map { a, b in
            String(format: "    <line x1=\"%.2f\" y1=\"%.2f\" x2=\"%.2f\" y2=\"%.2f\"/>",
                   a.x, s - a.y, b.x, s - b.y)
        }.joined(separator: "\n")

        let faceMarkup = faces.map { face in
            let points = face.points
                .map { String(format: "%.2f,%.2f", $0.x, s - $0.y) }
                .joined(separator: " ")
            return "    <polygon points=\"\(points)\" fill=\"\(hex(color(for: face.role, scheme: scheme)))\"/>"
        }.joined(separator: "\n")

        return """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
          <title>Blockpad</title>
          <defs>
            <linearGradient id="card" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0" stop-color="\(hex(lighten(scheme.card, scheme.cardLift)))"/>
              <stop offset="1" stop-color="\(hex(scheme.card))"/>
            </linearGradient>
          </defs>
          <rect x="\(fmt(card.minX))" y="\(fmt(card.minY))" width="\(fmt(card.width))" \
        height="\(fmt(card.height))" rx="\(fmt(radius))" ry="\(fmt(radius))" fill="url(#card)"/>
          <g stroke="\(hex(scheme.seam))" stroke-opacity="\(alpha(scheme.seam))" \
        stroke-width="\(fmt(card.width * seamWidth))" stroke-linecap="round">
        \(seamMarkup)
          </g>
          <g>
        \(faceMarkup)
          </g>
        </svg>
        """
    }

    private static func fmt(_ value: CGFloat) -> String {
        String(format: "%.2f", value)
    }
}
