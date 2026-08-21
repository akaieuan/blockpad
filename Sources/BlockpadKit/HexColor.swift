import Foundation

/// Colour as hex, because that is what a coding agent can act on.
///
/// The palette used to be five indices, and the tree said `[slate]`. A name is
/// a lookup the receiver cannot perform; `#55677A` is a value it can paste
/// straight into CSS. Storing hex also means arbitrary colours cost nothing
/// extra — the palette becomes a set of presets rather than the whole range.
public enum HexColor {

    /// Parses `#RGB`, `#RRGGBB`, `#RRGGBBAA`, with or without the hash.
    /// Returns components in 0...1.
    public static func components(_ hex: String) -> (r: Double, g: Double, b: Double, a: Double)? {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.allSatisfy({ $0.isHexDigit }) else { return nil }

        // #RGB is shorthand for #RRGGBB.
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        guard text.count == 6 || text.count == 8 else { return nil }
        guard let value = UInt32(text, radix: 16) else { return nil }

        if text.count == 6 {
            return (Double((value >> 16) & 0xFF) / 255,
                    Double((value >> 8) & 0xFF) / 255,
                    Double(value & 0xFF) / 255,
                    1)
        }
        return (Double((value >> 24) & 0xFF) / 255,
                Double((value >> 16) & 0xFF) / 255,
                Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255)
    }

    public static func string(r: Double, g: Double, b: Double) -> String {
        func byte(_ value: Double) -> Int { Int((max(0, min(1, value)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }

    public static func isValid(_ hex: String) -> Bool { components(hex) != nil }

    /// Normalises any accepted spelling to `#RRGGBB`, so two blocks that are the
    /// same colour compare equal and collapse into one run in the tree.
    public static func normalized(_ hex: String) -> String? {
        guard let c = components(hex) else { return nil }
        return string(r: c.r, g: c.g, b: c.b)
    }
}
