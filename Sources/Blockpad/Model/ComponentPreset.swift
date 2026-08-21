import CoreGraphics
import Foundation

enum ComponentCategory: String, CaseIterable, Identifiable {
    case layout = "Layout"
    case controls = "Controls"
    case data = "Data"
    case feedback = "Feedback"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .layout: return "square.split.2x2"
        case .controls: return "slider.horizontal.3"
        case .data: return "tablecells"
        case .feedback: return "bell"
        }
    }
}

/// Pre-composed blockouts.
///
/// These are not a component library and must not become one. Each preset lands
/// as plain blocks the instant it is placed — nothing to select, resize or
/// serialise differently — so the tree stays the only contract. They exist to
/// skip the boring thirty seconds of dragging six rectangles into a shape you
/// have drawn a hundred times.
struct ComponentPreset: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let category: ComponentCategory
    let size: CGSize
    let parts: [Part]

    struct Part {
        let kind: BlockKind
        /// Relative to the preset's origin.
        let rect: CGRect
        var text: String = ""
        /// Index into the preset palettes, resolved at build time. Presets stay
        /// on named colours so they follow the palette rather than freezing a
        /// hex the user cannot recognise later.
        var fill: Int = 0
        var color: Int = 0
        var stroke: Double? = nil
    }

    func build(at origin: CGPoint, style: Style) -> [Block] {
        parts.map { part in
            let strokeHex = Palette.strokePresets[
                max(0, min(Palette.strokePresets.count - 1, part.color))].hex
            let fillHex: String? = (part.kind.takesFill && part.fill > 0)
                ? Palette.fillPresets[min(Palette.fillPresets.count - 1, part.fill - 1)].hex
                : nil
            return Block(kind: part.kind,
                         rect: part.rect.offsetBy(dx: origin.x, dy: origin.y),
                         text: part.text,
                         stroke: strokeHex,
                         fill: fillHex,
                         fillStyle: fillHex == nil ? .none : style.fillStyle,
                         strokeWidth: part.stroke ?? style.strokeWidth,
                         cornerRadius: style.cornerRadius,
                         opacity: 1)
        }
    }

    static func inCategory(_ category: ComponentCategory) -> [ComponentPreset] {
        all.filter { $0.category == category }
    }

    // MARK: - Shorthand

    private static func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                            _ text: String = "", fill: Int = 0, color: Int = 0) -> Part {
        Part(kind: .box, rect: CGRect(x: x, y: y, width: w, height: h),
             text: text, fill: fill, color: color)
    }

    private static func label(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat,
                              _ text: String, color: Int = 0) -> Part {
        Part(kind: .text, rect: CGRect(x: x, y: y, width: w, height: 18),
             text: text, color: color)
    }

    private static func dot(_ x: CGFloat, _ y: CGFloat, _ d: CGFloat, fill: Int = 0, color: Int = 0) -> Part {
        Part(kind: .ellipse, rect: CGRect(x: x, y: y, width: d, height: d), fill: fill, color: color)
    }

    // MARK: - Library

    static let all: [ComponentPreset] = layout + controls + data + feedback

    // MARK: Layout

    static let layout: [ComponentPreset] = [
        ComponentPreset(id: "page", name: "Page", symbol: "rectangle.split.1x2",
                        category: .layout, size: CGSize(width: 560, height: 360), parts: [
            box(0, 0, 560, 56, fill: 1, color: 1),
            label(16, 19, 100, "Product"),
            box(0, 56, 560, 248),
            label(20, 80, 200, "Content", color: 1),
            box(0, 304, 560, 56, fill: 1, color: 1)
        ]),
        ComponentPreset(id: "sidebar", name: "Sidebar", symbol: "sidebar.left",
                        category: .layout, size: CGSize(width: 520, height: 340), parts: [
            box(0, 0, 520, 340),
            box(0, 0, 160, 340, fill: 1, color: 1),
            box(16, 24, 128, 28, "Nav", fill: 4),
            box(16, 60, 128, 28, color: 1),
            box(16, 96, 128, 28, color: 1),
            box(16, 132, 128, 28, color: 1),
            label(192, 28, 200, "Content")
        ]),
        ComponentPreset(id: "navbar", name: "Nav bar", symbol: "menubar.rectangle",
                        category: .layout, size: CGSize(width: 560, height: 56), parts: [
            box(0, 0, 560, 56),
            dot(16, 14, 28, fill: 1, color: 1),
            label(56, 19, 100, "Product"),
            label(300, 19, 60, "Docs", color: 1),
            label(372, 19, 70, "Pricing", color: 1),
            box(460, 12, 84, 32, "Sign in", fill: 4, color: 1)
        ]),
        ComponentPreset(id: "hero", name: "Hero", symbol: "rectangle.center.inset.filled",
                        category: .layout, size: CGSize(width: 560, height: 260), parts: [
            box(0, 0, 560, 260, fill: 1, color: 1),
            Part(kind: .text, rect: CGRect(x: 120, y: 70, width: 320, height: 30),
                 text: "Headline goes here", stroke: 3),
            label(120, 116, 320, "Supporting sentence underneath.", color: 1),
            box(120, 156, 120, 44, "Get started", fill: 4),
            box(252, 156, 120, 44, "Learn more", color: 1)
        ]),
        ComponentPreset(id: "split", name: "Split", symbol: "rectangle.split.2x1",
                        category: .layout, size: CGSize(width: 520, height: 260), parts: [
            box(0, 0, 252, 260, fill: 1, color: 1),
            box(268, 0, 252, 260),
            label(20, 24, 160, "Left", color: 1),
            label(288, 24, 160, "Right", color: 1)
        ]),
        ComponentPreset(id: "grid", name: "Grid", symbol: "square.grid.2x2",
                        category: .layout, size: CGSize(width: 520, height: 340), parts: {
            var parts: [Part] = []
            for row in 0..<2 {
                for column in 0..<3 {
                    parts.append(box(CGFloat(column) * 176, CGFloat(row) * 176, 160, 160,
                                     fill: 1, color: 1))
                }
            }
            return parts
        }()),
        ComponentPreset(id: "footer", name: "Footer", symbol: "rectangle.bottomthird.inset.filled",
                        category: .layout, size: CGSize(width: 560, height: 120), parts: [
            box(0, 0, 560, 120, fill: 1, color: 1),
            label(20, 22, 120, "Product"),
            label(20, 48, 100, "About", color: 1),
            label(20, 70, 100, "Careers", color: 1),
            label(200, 48, 100, "Docs", color: 1),
            label(200, 70, 100, "Support", color: 1),
            label(380, 90, 160, "© 2026", color: 1)
        ]),
        ComponentPreset(id: "card", name: "Card", symbol: "rectangle.portrait",
                        category: .layout, size: CGSize(width: 260, height: 200), parts: [
            box(0, 0, 260, 200),
            box(16, 16, 228, 96, fill: 1, color: 1),
            label(16, 126, 180, "Title"),
            label(16, 152, 200, "Supporting copy", color: 1)
        ])
    ]

    // MARK: Controls

    static let controls: [ComponentPreset] = [
        ComponentPreset(id: "button", name: "Button", symbol: "capsule",
                        category: .controls, size: CGSize(width: 128, height: 44), parts: [
            box(0, 0, 128, 44, "Button", fill: 4)
        ]),
        ComponentPreset(id: "buttonpair", name: "Actions", symbol: "rectangle.on.rectangle",
                        category: .controls, size: CGSize(width: 232, height: 44), parts: [
            box(0, 0, 104, 44, "Cancel", color: 1),
            box(120, 0, 112, 44, "Confirm", fill: 4)
        ]),
        ComponentPreset(id: "input", name: "Input", symbol: "character.cursor.ibeam",
                        category: .controls, size: CGSize(width: 280, height: 66), parts: [
            label(0, 0, 140, "Label", color: 1),
            box(0, 24, 280, 42, color: 1)
        ]),
        ComponentPreset(id: "search", name: "Search", symbol: "magnifyingglass",
                        category: .controls, size: CGSize(width: 280, height: 40), parts: [
            box(0, 0, 280, 40, fill: 1, color: 1),
            dot(12, 12, 16, color: 1),
            label(40, 11, 160, "Search", color: 1)
        ]),
        ComponentPreset(id: "select", name: "Select", symbol: "chevron.up.chevron.down",
                        category: .controls, size: CGSize(width: 220, height: 42), parts: [
            box(0, 0, 220, 42, color: 1),
            label(14, 12, 120, "Choose one", color: 1),
            box(190, 16, 14, 10, color: 1)
        ]),
        ComponentPreset(id: "checkbox", name: "Checkbox", symbol: "checkmark.square",
                        category: .controls, size: CGSize(width: 220, height: 88), parts: [
            box(0, 0, 22, 22, fill: 3, color: 3),
            label(34, 2, 180, "Option one", color: 1),
            box(0, 33, 22, 22, color: 1),
            label(34, 35, 180, "Option two", color: 1),
            box(0, 66, 22, 22, color: 1),
            label(34, 68, 180, "Option three", color: 1)
        ]),
        ComponentPreset(id: "radio", name: "Radio", symbol: "circle.circle",
                        category: .controls, size: CGSize(width: 220, height: 88), parts: [
            dot(0, 0, 22, fill: 4, color: 3),
            label(34, 2, 180, "Choice A", color: 1),
            dot(0, 33, 22, color: 1),
            label(34, 35, 180, "Choice B", color: 1),
            dot(0, 66, 22, color: 1),
            label(34, 68, 180, "Choice C", color: 1)
        ]),
        ComponentPreset(id: "toggle", name: "Toggle", symbol: "switch.2",
                        category: .controls, size: CGSize(width: 200, height: 28), parts: [
            box(0, 0, 48, 28, fill: 3, color: 3),
            dot(24, 2, 24, fill: 1),
            label(62, 5, 130, "Enabled", color: 1)
        ]),
        ComponentPreset(id: "slider", name: "Slider", symbol: "slider.horizontal.below.rectangle",
                        category: .controls, size: CGSize(width: 240, height: 24), parts: [
            box(0, 9, 240, 6, fill: 1, color: 1),
            box(0, 9, 150, 6, fill: 4, color: 4),
            dot(138, 0, 24, fill: 1)
        ]),
        ComponentPreset(id: "segmented", name: "Segmented", symbol: "square.split.3x1",
                        category: .controls, size: CGSize(width: 300, height: 36), parts: [
            box(0, 0, 100, 36, "Day", fill: 4),
            box(100, 0, 100, 36, "Week", color: 1),
            box(200, 0, 100, 36, "Month", color: 1)
        ]),
        ComponentPreset(id: "tabs", name: "Tabs", symbol: "square.grid.3x1.below.line.grid.1x2",
                        category: .controls, size: CGSize(width: 420, height: 44), parts: [
            box(0, 0, 140, 44, "All", fill: 1),
            box(140, 0, 140, 44, "Active", color: 1),
            box(280, 0, 140, 44, "Archived", color: 1)
        ]),
        ComponentPreset(id: "form", name: "Form", symbol: "list.bullet.rectangle",
                        category: .controls, size: CGSize(width: 320, height: 280), parts: [
            label(0, 0, 160, "Email", color: 1),
            box(0, 26, 320, 44, color: 1),
            label(0, 90, 160, "Password", color: 1),
            box(0, 116, 320, 44, color: 1),
            box(0, 186, 22, 22, fill: 3, color: 3),
            label(34, 188, 200, "Remember me", color: 1),
            box(0, 234, 320, 46, "Continue", fill: 4)
        ])
    ]

    // MARK: Data

    static let data: [ComponentPreset] = [
        ComponentPreset(id: "table", name: "Table", symbol: "tablecells",
                        category: .data, size: CGSize(width: 460, height: 260), parts: {
            var parts = [box(0, 0, 460, 260),
                         box(0, 0, 460, 44, "Name          Status          Date", fill: 1, color: 1)]
            for row in 0..<4 {
                parts.append(box(0, 44 + CGFloat(row) * 54, 460, 54, color: 1))
            }
            return parts
        }()),
        ComponentPreset(id: "list", name: "List", symbol: "list.bullet",
                        category: .data, size: CGSize(width: 420, height: 288), parts: {
            var parts: [Part] = []
            for row in 0..<4 {
                let y = CGFloat(row) * 72
                parts.append(box(0, y, 420, 64))
                parts.append(box(16, y + 20, 24, 24, color: 3))
                parts.append(label(56, y + 23, 180, "Item", color: 1))
            }
            return parts
        }()),
        ComponentPreset(id: "stats", name: "Stats", symbol: "number.square",
                        category: .data, size: CGSize(width: 520, height: 110), parts: {
            var parts: [Part] = []
            for column in 0..<3 {
                let x = CGFloat(column) * 176
                parts.append(box(x, 0, 160, 110, fill: 1, color: 1))
                parts.append(label(x + 16, 20, 120, "Metric", color: 1))
                parts.append(Part(kind: .text, rect: CGRect(x: x + 16, y: 48, width: 120, height: 28),
                                  text: "1,234", stroke: 3))
            }
            return parts
        }()),
        ComponentPreset(id: "chart", name: "Chart", symbol: "chart.bar",
                        category: .data, size: CGSize(width: 360, height: 220), parts: {
            var parts = [box(0, 0, 360, 220)]
            let heights: [CGFloat] = [70, 120, 95, 150, 110, 165]
            for (index, height) in heights.enumerated() {
                let x = 28 + CGFloat(index) * 52
                parts.append(box(x, 180 - height, 36, height, fill: 4, color: 4))
            }
            return parts
        }()),
        ComponentPreset(id: "kanban", name: "Kanban", symbol: "rectangle.split.3x1",
                        category: .data, size: CGSize(width: 520, height: 300), parts: {
            var parts: [Part] = []
            for column in 0..<3 {
                let x = CGFloat(column) * 176
                parts.append(box(x, 0, 160, 300, fill: 1, color: 1))
                parts.append(label(x + 14, 12, 120, "Column", color: 1))
                for card in 0..<2 {
                    parts.append(box(x + 12, 44 + CGFloat(card) * 76, 136, 64))
                }
            }
            return parts
        }()),
        ComponentPreset(id: "timeline", name: "Timeline", symbol: "point.topleft.down.curvedto.point.bottomright.up",
                        category: .data, size: CGSize(width: 320, height: 240), parts: {
            var parts: [Part] = []
            for step in 0..<4 {
                let y = CGFloat(step) * 62
                parts.append(dot(0, y, 20, fill: 4, color: 4))
                parts.append(label(36, y + 1, 240, "Event", color: 1))
                if step < 3 {
                    parts.append(Part(kind: .line, rect: CGRect(x: 10, y: y + 22, width: 0, height: 38),
                                      color: 1))
                }
            }
            return parts
        }()),
        ComponentPreset(id: "avatars", name: "Avatars", symbol: "person.2",
                        category: .data, size: CGSize(width: 300, height: 56), parts: {
            var parts: [Part] = []
            for index in 0..<4 {
                let x = CGFloat(index) * 44
                parts.append(dot(x, 0, 44, fill: index % 2 == 0 ? 1 : 4, color: 1))
            }
            parts.append(label(196, 15, 100, "+12 more", color: 1))
            return parts
        }()),
        ComponentPreset(id: "pagination", name: "Pages", symbol: "ellipsis.rectangle",
                        category: .data, size: CGSize(width: 280, height: 36), parts: [
            box(0, 0, 36, 36, "‹", color: 1),
            box(44, 0, 36, 36, "1", fill: 4),
            box(88, 0, 36, 36, "2", color: 1),
            box(132, 0, 36, 36, "3", color: 1),
            box(176, 0, 36, 36, "›", color: 1)
        ])
    ]

    // MARK: Feedback

    static let feedback: [ComponentPreset] = [
        ComponentPreset(id: "dialog", name: "Dialog", symbol: "macwindow",
                        category: .feedback, size: CGSize(width: 380, height: 220), parts: [
            box(0, 0, 380, 220),
            label(20, 22, 240, "Are you sure?"),
            label(20, 54, 300, "This cannot be undone.", color: 1),
            box(148, 156, 100, 40, "Cancel", color: 1),
            box(260, 156, 100, 40, "Delete", fill: 2, color: 2)
        ]),
        ComponentPreset(id: "toast", name: "Toast", symbol: "bell.badge",
                        category: .feedback, size: CGSize(width: 320, height: 56), parts: [
            box(0, 0, 320, 56, fill: 3, color: 3),
            dot(14, 18, 20, fill: 3, color: 3),
            label(46, 18, 200, "Saved successfully")
        ]),
        ComponentPreset(id: "banner", name: "Banner", symbol: "exclamationmark.triangle",
                        category: .feedback, size: CGSize(width: 420, height: 60), parts: [
            box(0, 0, 420, 60, fill: 5, color: 4),
            dot(16, 20, 20, color: 4),
            label(48, 20, 280, "Heads up — something needs attention", color: 1)
        ]),
        ComponentPreset(id: "empty", name: "Empty", symbol: "tray",
                        category: .feedback, size: CGSize(width: 340, height: 200), parts: [
            box(134, 0, 72, 72, fill: 1, color: 1),
            Part(kind: .text, rect: CGRect(x: 60, y: 92, width: 220, height: 24),
                 text: "Nothing here yet", stroke: 3),
            label(50, 124, 240, "Create your first item to begin.", color: 1),
            box(110, 156, 120, 40, "Create", fill: 4)
        ]),
        ComponentPreset(id: "progress", name: "Progress", symbol: "chart.bar.horizontal.page",
                        category: .feedback, size: CGSize(width: 280, height: 40), parts: [
            label(0, 0, 160, "Uploading", color: 1),
            box(0, 26, 280, 12, fill: 1, color: 1),
            box(0, 26, 180, 12, fill: 3, color: 3)
        ]),
        ComponentPreset(id: "badges", name: "Badges", symbol: "seal",
                        category: .feedback, size: CGSize(width: 300, height: 28), parts: [
            box(0, 0, 76, 28, "Active", fill: 3, color: 3),
            box(88, 0, 76, 28, "Pending", fill: 5, color: 4),
            box(176, 0, 76, 28, "Failed", fill: 2, color: 2)
        ])
    ]
}
