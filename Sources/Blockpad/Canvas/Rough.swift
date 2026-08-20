import CoreGraphics
import Foundation

/// Deterministic RNG so a block's roughness is identical on every redraw.
/// Without this the sketch shimmers whenever the view invalidates.
struct SeededRNG {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    /// Uniform in [0, 1).
    mutating func unit() -> CGFloat {
        CGFloat(next() >> 11) / CGFloat(UInt64(1) << 53)
    }
}

/// Hand-drawn stroke generation (§4): subdivide, perturb with seeded noise,
/// stroke twice at a slight offset. The geometry follows rough.js's line
/// algorithm — a bowed cubic with randomized endpoints and control points.
///
/// Roughness signals provisional. A crisp rectangle reads as a spec and invites
/// the model to treat proportions as exact; a sketchy one reads as intent.
struct Rough {
    var rng: SeededRNG
    var roughness: CGFloat = 1.0
    var bowing: CGFloat = 1.0

    private let maxRandomnessOffset: CGFloat = 2.0

    init(seed: UInt64, roughness: CGFloat = 1.0, bowing: CGFloat = 1.0) {
        self.rng = SeededRNG(seed: seed)
        self.roughness = roughness
        self.bowing = bowing
    }

    private mutating func offset(_ min: CGFloat, _ max: CGFloat, _ gain: CGFloat) -> CGFloat {
        roughness * gain * (rng.unit() * (max - min) + min)
    }

    private mutating func offsetSym(_ x: CGFloat, _ gain: CGFloat) -> CGFloat {
        offset(-x, x, gain)
    }

    /// One pass of a rough line. `overlay` is the tighter second pass.
    mutating func line(_ p1: CGPoint, _ p2: CGPoint, into path: CGMutablePath, move: Bool, overlay: Bool) {
        let dx = p2.x - p1.x
        let dy = p2.y - p1.y
        let lengthSq = dx * dx + dy * dy
        let length = sqrt(lengthSq)

        // Long lines get proportionally less wobble or they look broken.
        let gain: CGFloat
        if length < 200 { gain = 1 }
        else if length > 500 { gain = 0.4 }
        else { gain = -0.0016668 * length + 1.233334 }

        var off = maxRandomnessOffset
        if off * off * 100 > lengthSq { off = length / 10 }
        let halfOff = off / 2
        let amount = overlay ? halfOff : off

        let divergePoint = 0.2 + rng.unit() * 0.2
        var midDispX = bowing * maxRandomnessOffset * dy / 200
        var midDispY = bowing * maxRandomnessOffset * -dx / 200
        midDispX = offsetSym(midDispX, gain)
        midDispY = offsetSym(midDispY, gain)

        if move {
            path.move(to: CGPoint(x: p1.x + offsetSym(amount, gain),
                                  y: p1.y + offsetSym(amount, gain)))
        }

        let c1 = CGPoint(x: midDispX + p1.x + dx * divergePoint + offsetSym(amount, gain),
                         y: midDispY + p1.y + dy * divergePoint + offsetSym(amount, gain))
        let c2 = CGPoint(x: midDispX + p1.x + 2 * dx * divergePoint + offsetSym(amount, gain),
                         y: midDispY + p1.y + 2 * dy * divergePoint + offsetSym(amount, gain))
        let end = CGPoint(x: p2.x + offsetSym(amount, gain),
                          y: p2.y + offsetSym(amount, gain))
        path.addCurve(to: end, control1: c1, control2: c2)
    }

    /// Two passes, the signature Excalidraw double-stroke.
    mutating func doubleLine(_ p1: CGPoint, _ p2: CGPoint, into path: CGMutablePath) {
        line(p1, p2, into: path, move: true, overlay: false)
        line(p1, p2, into: path, move: true, overlay: true)
    }

    mutating func rectangle(_ r: CGRect) -> CGPath {
        let path = CGMutablePath()
        let tl = CGPoint(x: r.minX, y: r.minY)
        let tr = CGPoint(x: r.maxX, y: r.minY)
        let br = CGPoint(x: r.maxX, y: r.maxY)
        let bl = CGPoint(x: r.minX, y: r.maxY)
        doubleLine(tl, tr, into: path)
        doubleLine(tr, br, into: path)
        doubleLine(br, bl, into: path)
        doubleLine(bl, tl, into: path)
        return path
    }

    mutating func polyline(_ points: [CGPoint], closed: Bool = false) -> CGPath {
        let path = CGMutablePath()
        guard points.count > 1 else { return path }
        for i in 0..<(points.count - 1) {
            doubleLine(points[i], points[i + 1], into: path)
        }
        if closed, let first = points.first, let last = points.last {
            doubleLine(last, first, into: path)
        }
        return path
    }

    mutating func lineSegment(_ p1: CGPoint, _ p2: CGPoint) -> CGPath {
        let path = CGMutablePath()
        doubleLine(p1, p2, into: path)
        return path
    }

    /// A slightly-off ellipse, drawn as a perturbed closed spline.
    mutating func ellipse(_ r: CGRect) -> CGPath {
        let path = CGMutablePath()
        let steps = 9
        let rx = r.width / 2
        let ry = r.height / 2
        let cx = r.midX
        let cy = r.midY
        var pts: [CGPoint] = []
        let start = rng.unit() * 2 * .pi
        for i in 0..<steps {
            let a = start + CGFloat(i) / CGFloat(steps) * 2 * .pi
            let jitterX = offsetSym(rx * 0.03, 1)
            let jitterY = offsetSym(ry * 0.03, 1)
            pts.append(CGPoint(x: cx + rx * cos(a) + jitterX,
                               y: cy + ry * sin(a) + jitterY))
        }
        guard let first = pts.first else { return path }
        path.move(to: first)
        for i in 0..<pts.count {
            let cur = pts[i]
            let nxt = pts[(i + 1) % pts.count]
            let mid = CGPoint(x: (cur.x + nxt.x) / 2, y: (cur.y + nxt.y) / 2)
            path.addQuadCurve(to: mid, control: cur)
        }
        path.closeSubpath()
        return path
    }
}
