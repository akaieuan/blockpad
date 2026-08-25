import AppKit
import BlockpadKit

/// Five stroke swatches, no picker (§3). Ink, slate, dusty red, sage, amber.
struct ColorPreset: Identifiable, Hashable {
    var id: String { hex }
    let name: String
    let hex: String

    var nsColor: NSColor {
        guard let c = HexColor.components(hex) else { return .black }
        return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
    }
}

/// Presets, not the range.
///
/// §3 said five swatches and no picker, and §11 listed a colour picker as a
/// non-goal. Both are reversed deliberately: colour is now arbitrary hex, and
/// these are one-click starting points. The tree gains from it too — `#55677A`
/// is a value the receiving agent can paste into CSS, where `[slate]` was a
/// lookup it could not perform.
enum Palette {

    static let defaultStroke = "#2B2A28"

    static let strokePresets: [ColorPreset] = [
        ColorPreset(name: "Ink", hex: "#2B2A28"),
        ColorPreset(name: "Slate", hex: "#55677A"),
        ColorPreset(name: "Dusty red", hex: "#B4534A"),
        ColorPreset(name: "Sage", hex: "#6E8B6A"),
        ColorPreset(name: "Amber", hex: "#C08A2E"),
        ColorPreset(name: "Indigo", hex: "#5A55DA"),
        ColorPreset(name: "Teal", hex: "#2F7E7A"),
        ColorPreset(name: "Plum", hex: "#7A4A78")
    ]

    static let fillPresets: [ColorPreset] = [
        ColorPreset(name: "Stone", hex: "#E5E3DF"),
        ColorPreset(name: "Blush", hex: "#F6DAD5"),
        ColorPreset(name: "Sage", hex: "#DDEADA"),
        ColorPreset(name: "Sky", hex: "#DAE5EF"),
        ColorPreset(name: "Sand", hex: "#FAEAC7"),
        ColorPreset(name: "Lilac", hex: "#E3E0F7"),
        ColorPreset(name: "White", hex: "#FFFFFF"),
        ColorPreset(name: "Charcoal", hex: "#3A3A3C")
    ]

    static func color(_ hex: String) -> NSColor {
        guard let c = HexColor.components(hex) else { return .black }
        return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: c.a)
    }

    /// Rule warnings. Amber rather than red: a sketch that breaks a guideline
    /// is unfinished, not broken.
    static let warning = NSColor(srgbRed: 0.85, green: 0.55, blue: 0.13, alpha: 0.95)
    static let selection = NSColor(srgbRed: 0.353, green: 0.333, blue: 0.855, alpha: 1)
    /// Alignment guides read as a different system from selection, so they get
    /// their own hue rather than a lighter tint of it.
    static let guide = NSColor(srgbRed: 0.910, green: 0.275, blue: 0.486, alpha: 1)
}

/// Canvas background, switchable (asked for directly, not in the original §4).
struct CanvasTheme: Identifiable, Hashable, Codable {
    var id: String { name }
    let name: String
    let background: RGBA
    let isDark: Bool

    var color: NSColor { background.nsColor }

    /// The paper as hex, for contrast checks: a text block's label sits on this
    /// rather than on a fill of its own.
    var hex: String {
        HexColor.string(r: Double(background.r), g: Double(background.g), b: Double(background.b))
    }

    /// Grid and frame chrome have to invert on a dark ground or they vanish.
    var gridColor: NSColor {
        isDark ? NSColor(white: 1, alpha: 0.10) : NSColor(srgbRed: 0.169, green: 0.165, blue: 0.157, alpha: 0.07)
    }

    var sheetColor: NSColor {
        isDark ? NSColor(white: 1, alpha: 0.04) : NSColor(srgbRed: 0.996, green: 0.996, blue: 0.992, alpha: 1)
    }

    var frameStroke: NSColor {
        isDark ? NSColor(white: 1, alpha: 0.22) : NSColor(srgbRed: 0.169, green: 0.165, blue: 0.157, alpha: 0.28)
    }

    /// Near-black ink is invisible on a dark ground, so it flips to a warm
    /// off-white. Keyed off luminance rather than a palette index, because with
    /// arbitrary colours there is no index to check.
    func inkAdjusted(_ color: NSColor) -> NSColor {
        guard isDark, let srgb = color.usingColorSpace(.sRGB) else { return color }
        let luminance = 0.2126 * srgb.redComponent
            + 0.7152 * srgb.greenComponent
            + 0.0722 * srgb.blueComponent
        guard luminance < 0.25 else { return color }
        return NSColor(srgbRed: 0.933, green: 0.925, blue: 0.906, alpha: 1)
    }

    static let all: [CanvasTheme] = [
        CanvasTheme(name: "Paper", background: RGBA(0.980, 0.980, 0.973), isDark: false),
        CanvasTheme(name: "White", background: RGBA(1, 1, 1), isDark: false),
        CanvasTheme(name: "Warm", background: RGBA(0.961, 0.941, 0.906), isDark: false),
        CanvasTheme(name: "Cool", background: RGBA(0.937, 0.953, 0.969), isDark: false),
        CanvasTheme(name: "Slate", background: RGBA(0.114, 0.118, 0.129), isDark: true)
    ]

    static var paper: CanvasTheme { all[0] }
}

/// NSColor is not Codable, so themes persist as components.
struct RGBA: Hashable, Codable {
    var r: Double, g: Double, b: Double, a: Double

    init(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) {
        self.r = r; self.g = g; self.b = b; self.a = a
    }

    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
}

enum StrokeWeight {
    /// Quick presets. Width itself is a free number now.
    static let presets: [(name: String, width: Double)] = [
        ("Hairline", 1), ("Thin", 1.5), ("Medium", 2), ("Bold", 3), ("Heavy", 5)
    ]
    static let range: ClosedRange<Double> = 0...24
}

/// Reference frame presets (§3).
struct FramePreset: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let size: CGSize

    static let all: [FramePreset] = [
        FramePreset(name: "Desktop", size: CGSize(width: 1440, height: 900)),
        FramePreset(name: "Tablet", size: CGSize(width: 834, height: 1112)),
        FramePreset(name: "Mobile", size: CGSize(width: 390, height: 844))
    ]
}
