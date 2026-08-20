import Foundation

/// One source of truth for the toolbar, the shortcuts and the tooltips, so a
/// tool can never appear in the bar without a key or vice versa.
struct ToolSpec: Identifiable {
    let id: String
    let tool: Tool
    let symbol: String
    let label: String
    /// Mnemonic letter, the way people actually learn a canvas app.
    let key: String
    /// Positional digit, the way Excalidraw teaches it.
    let digit: String

    static let all: [ToolSpec] = [
        ToolSpec(id: "select",  tool: .select,          symbol: "cursorarrow",       label: "Select",    key: "v", digit: "1"),
        ToolSpec(id: "hand",    tool: .hand,            symbol: "hand.raised",       label: "Pan",       key: "h", digit: "2"),
        ToolSpec(id: "frame",   tool: .draw(.frame),    symbol: "rectangle.dashed",  label: "Frame",     key: "f", digit: "3"),
        ToolSpec(id: "box",     tool: .draw(.box),      symbol: "square",            label: "Rectangle", key: "r", digit: "4"),
        ToolSpec(id: "ellipse", tool: .draw(.ellipse),  symbol: "circle",            label: "Ellipse",   key: "o", digit: "5"),
        ToolSpec(id: "diamond", tool: .draw(.diamond),  symbol: "diamond",           label: "Diamond",   key: "d", digit: "6"),
        ToolSpec(id: "arrow",   tool: .draw(.arrow),    symbol: "arrow.right",       label: "Arrow",     key: "a", digit: "7"),
        ToolSpec(id: "line",    tool: .draw(.line),     symbol: "line.diagonal",     label: "Line",      key: "l", digit: "8"),
        ToolSpec(id: "pen",     tool: .draw(.pen),      symbol: "scribble",          label: "Draw",      key: "p", digit: "9"),
        ToolSpec(id: "text",    tool: .draw(.text),     symbol: "character",         label: "Text",      key: "t", digit: "0"),
        ToolSpec(id: "eraser",  tool: .eraser,          symbol: "eraser",            label: "Eraser",    key: "e", digit: "")
    ]
}

enum Shortcuts {
    static func tool(for characters: String) -> Tool? {
        ToolSpec.all.first { $0.key == characters || (!$0.digit.isEmpty && $0.digit == characters) }?.tool
    }
}
