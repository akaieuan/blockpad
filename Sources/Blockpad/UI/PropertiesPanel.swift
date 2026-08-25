import SwiftUI
import BlockpadKit

/// The inspector rail.
///
/// Rows, not blocks: leading glyph, quiet label, control on the trailing edge,
/// hairline between. Two things the first pass got wrong and this one fixes —
/// the hairlines ran into the panel's rounded corners, and the last row drew one
/// against the container edge. Both are why it read as spilling rather than
/// contained.
struct PropertiesPanel: View {
    @ObservedObject var store: SketchStore
    var width: CGFloat = 190
    /// The rail scrolls rather than overflowing when the window is short.
    var maxHeight: CGFloat = .infinity
    var canvas: () -> CanvasView?

    private var hasSelection: Bool { !store.selection.isEmpty }
    private var showsShapeProperties: Bool { hasSelection || store.tool.isDrawing }
    private var style: Style { store.effectiveStyle }

    /// Angle and bow only mean anything for a connector.
    private var linearSelection: [Block] {
        store.selectedBlocks.filter { $0.kind.isLinear }
    }

    private var showsConnector: Bool {
        if hasSelection { return !linearSelection.isEmpty }
        return store.tool.kind?.isLinear ?? false
    }

    /// Heading in degrees, 0 pointing right, counting clockwise because the
    /// canvas is y-down.
    private var connectorAngle: Double {
        guard let first = linearSelection.first else { return 0 }
        let radians = Connector.angle(of: first.rect)
        let degrees = Double(radians * 180 / .pi)
        return degrees < 0 ? degrees + 360 : degrees
    }

    private var connectorCurve: Double {
        (linearSelection.first?.curve ?? 0) * 100
    }

    /// Text size only means something for a block that can carry text.
    private var showsTextSize: Bool {
        if hasSelection { return store.selectedBlocks.contains { $0.kind.takesText } }
        return store.tool.kind?.takesText ?? false
    }

    /// What the size control should show when nothing explicit is set: the size
    /// the text is actually rendering at, derived from stroke weight.
    private var effectiveFontSize: Double {
        if let explicit = style.fontSize { return explicit }
        return Double(BlockRenderer.fontSize(forStrokeWidth: style.strokeWidth))
    }

    /// Fill only means something for closed shapes; offering it for an arrow is
    /// how an inspector starts feeling like a settings screen.
    private var showsFill: Bool {
        if hasSelection { return store.selectedBlocks.contains { $0.kind.takesFill } }
        return store.tool.kind?.takesFill ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    if showsShapeProperties { shapeRows } else { canvasRows }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)
        }
        .padding(.bottom, Token.Space.md)
        .frame(minWidth: width, alignment: .leading)
        .frame(maxHeight: maxHeight)
        // Width comes from the widest row, not from a guess. Height still
        // yields to maxHeight so the rail scrolls rather than passing the dock.
        .fixedSize(horizontal: true, vertical: true)
        .glassSurface()
        .animation(.easeOut(duration: 0.16), value: showsShapeProperties)
        .animation(.easeOut(duration: 0.16), value: showsFill)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Token.Space.md) {
            Text(title)
                .font(Token.Text.header)
                .foregroundStyle(.primary.opacity(Token.Ink.strong))
            Spacer(minLength: Token.Space.sm)
            if store.selection.count > 1 {
                Text("\(store.selection.count)")
                    .font(Token.Text.micro)
                    .monospacedDigit()
                    .foregroundStyle(Token.accent)
                    .padding(.horizontal, Token.Space.md)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Token.accentSoft))
            }
        }
        .padding(.horizontal, Token.Size.separatorInset)
        .padding(.top, Token.Space.lg + 2)
        .padding(.bottom, Token.Space.lg)
    }

    private var title: String {
        if hasSelection {
            let kinds = Set(store.selectedBlocks.map(\.kind))
            return kinds.count == 1 ? (kinds.first?.label ?? "Selection") : "Selection"
        }
        if let kind = store.tool.kind { return kind.label }
        return "Canvas"
    }

    // MARK: - Rows

    /// Built as a list so the last row can drop its separator without every call
    /// site having to know whether it is last.
    @ViewBuilder
    private var shapeRows: some View {
        let rows: [RowSpec] = shapeRowSpecs
        ForEach(rows.indices, id: \.self) { index in
            Row(spec: rows[index], isLast: index == rows.count - 1)
        }
    }

    @ViewBuilder
    private var canvasRows: some View {
        let rows: [RowSpec] = canvasRowSpecs
        ForEach(rows.indices, id: \.self) { index in
            Row(spec: rows[index], isLast: index == rows.count - 1)
        }
    }

    private var shapeRowSpecs: [RowSpec] {
        var rows: [RowSpec] = []

        rows.append(RowSpec(id: "stroke", glyph: "scribble", label: "Stroke") {
            AnyView(ColorControl(current: style.stroke,
                                 presets: Palette.strokePresets,
                                 recents: store.recentColors,
                                 allowsNone: false) { hex in
                guard let hex else { return }
                store.style.stroke = hex
                store.noteRecent(hex)
                canvas()?.applyStyle({ $0.stroke = hex }, name: "Stroke Colour")
            })
        })

        rows.append(RowSpec(id: "weight", glyph: "lineweight", label: "Weight") {
            AnyView(NumberControl(value: style.strokeWidth,
                                  range: StrokeWeight.range,
                                  step: 0.5,
                                  presets: StrokeWeight.presets.map(\.width)) { width in
                store.style.strokeWidth = width
                canvas()?.applyStyle({ $0.strokeWidth = width }, name: "Stroke Width")
            })
        })

        if showsFill {
            rows.append(RowSpec(id: "fill", glyph: "paintbrush", label: "Fill") {
                AnyView(ColorControl(current: style.fill,
                                     presets: Palette.fillPresets,
                                     recents: store.recentColors,
                                     allowsNone: true) { hex in
                    store.style.fill = hex
                    if let hex { store.noteRecent(hex) }
                    canvas()?.applyStyle({ block in
                        guard block.kind.takesFill else { return }
                        block.fill = hex
                        // Choosing a colour while the style is none is a request
                        // to see it, not a no-op.
                        if hex != nil, block.fillStyle == .none { block.fillStyle = .solid }
                    }, name: "Fill")
                })
            })

            if style.fill != nil {
                rows.append(RowSpec(id: "pattern", glyph: "square.on.square.dashed", label: "Pattern") {
                    AnyView(Segments(count: FillStyle.allCases.count,
                                     selected: FillStyle.allCases.firstIndex(of: style.fillStyle) ?? 0,
                                     names: FillStyle.allCases.map(\.label)) { index in
                        FillGlyph(style: FillStyle.allCases[index])
                    } action: { index in
                        let value = FillStyle.allCases[index]
                        store.style.fillStyle = value
                        canvas()?.applyStyle({ $0.fillStyle = value }, name: "Fill Style")
                    })
                })
            }

            rows.append(RowSpec(id: "radius", glyph: "app.dashed", label: "Radius") {
                AnyView(NumberControl(value: style.cornerRadius,
                                      range: 0...120,
                                      step: 1,
                                      presets: [0, 4, 8, 12, 24, 999]) { radius in
                    store.style.cornerRadius = radius
                    canvas()?.applyStyle({ $0.cornerRadius = radius }, name: "Radius")
                })
            })
        }

        if showsTextSize {
            rows.append(RowSpec(id: "textSize", glyph: "textformat.size", label: "Text") {
                AnyView(NumberControl(value: effectiveFontSize,
                                      range: BlockRenderer.fontSizeRange,
                                      step: 1,
                                      presets: [12, 14, 18, 24, 36, 48, 72]) { size in
                    store.style.fontSize = size
                    canvas()?.applyStyle({ block in
                        guard block.kind.takesText else { return }
                        block.fontSize = size
                        // A text block is sized by its type, so the box has to
                        // follow or the selection outline drifts off the glyphs.
                        if block.kind == .text, !block.text.isEmpty {
                            block.rect = CGRect(origin: block.rect.standardized.origin,
                                                size: BlockRenderer.measure(block.text,
                                                                            size: CGFloat(size)))
                        }
                    }, name: "Text Size")
                })
            })
        }

        if showsConnector, hasSelection {
            rows.append(RowSpec(id: "angle", glyph: "angle", label: "Angle") {
                AnyView(NumberControl(value: connectorAngle,
                                      range: 0...360,
                                      step: 1,
                                      wraps: true,
                                      unit: "°",
                                      presets: [0, 45, 90, 135, 180, 225, 270, 315]) { degrees in
                    let radians = CGFloat(degrees) * .pi / 180
                    canvas()?.applyStyle({ block in
                        guard block.kind.isLinear else { return }
                        let start = Connector.endpoints(of: block.rect).start
                        block.rect = Connector.rect(from: start, angle: radians,
                                                    length: Connector.length(of: block.rect))
                    }, name: "Angle")
                })
            })

            rows.append(RowSpec(id: "curve", glyph: "point.topleft.down.to.point.bottomright.curvepath",
                                label: "Bow") {
                AnyView(NumberControl(value: connectorCurve,
                                      range: -150...150,
                                      step: 5,
                                      unit: "%",
                                      presets: [-60, -30, 0, 30, 60]) { percent in
                    canvas()?.applyStyle({ block in
                        guard block.kind.isLinear else { return }
                        block.curve = percent / 100
                    }, name: "Bow")
                })
            })
        }

        rows.append(RowSpec(id: "opacity", glyph: "circle.lefthalf.filled", label: "Opacity",
                            value: "\(Int(style.opacity * 100))%") {
            AnyView(Slider(value: Binding(
                get: { style.opacity },
                set: { value in
                    store.style.opacity = value
                    canvas()?.applyStyle({ $0.opacity = value }, name: "Opacity")
                }
            ), in: 0.1...1)
            .controlSize(.mini)
            .frame(width: 60))
        })

        if hasSelection {
            rows.append(RowSpec(id: "order", glyph: "square.2.layers.3d", label: "Order") {
                AnyView(HStack(spacing: 0) {
                    MiniButton(symbol: "square.3.stack.3d.bottom.filled", help: "Send to back   ⇧⌘[") {
                        canvas()?.reorder(toFront: true, forward: false)
                    }
                    MiniButton(symbol: "arrow.down", help: "Send backward   ⌘[") {
                        canvas()?.reorder(toFront: false, forward: false)
                    }
                    MiniButton(symbol: "arrow.up", help: "Bring forward   ⌘]") {
                        canvas()?.reorder(toFront: false, forward: true)
                    }
                    MiniButton(symbol: "square.3.stack.3d.top.filled", help: "Bring to front   ⇧⌘]") {
                        canvas()?.reorder(toFront: true, forward: true)
                    }
                })
            })

            rows.append(RowSpec(id: "edit", glyph: "hammer", label: "Edit") {
                AnyView(HStack(spacing: 0) {
                    MiniButton(symbol: "plus.square.on.square", help: "Duplicate   ⌘D") {
                        canvas()?.duplicateSelection()
                    }
                    MiniButton(symbol: "trash", help: "Delete   ⌫") {
                        canvas()?.deleteSelection()
                    }
                })
            })
        }

        return rows
    }

    private var canvasRowSpecs: [RowSpec] {
        [
            RowSpec(id: "theme", glyph: "square.grid.3x3", label: "Paper") {
                AnyView(Swatches(colors: CanvasTheme.all.map { Color(nsColor: $0.color) },
                                 names: CanvasTheme.all.map(\.name),
                                 selected: CanvasTheme.all.firstIndex(of: store.theme) ?? 0) { index in
                    store.theme = CanvasTheme.all[index]
                })
            },
            RowSpec(id: "render", glyph: "pencil.and.outline", label: "Render") {
                AnyView(Segments(count: 2, selected: store.sketchy ? 1 : 0,
                                 names: ["Crisp", "Sketch"]) { index in
                    RenderGlyph(sketchy: index == 1)
                } action: { index in
                    store.sketchy = index == 1
                })
            },
            RowSpec(id: "frame", glyph: "rectangle.dashed", label: "Frame") {
                AnyView(Menu {
                    ForEach(FramePreset.all) { preset in
                        Button("\(preset.name)  \(Int(preset.size.width))×\(Int(preset.size.height))") {
                            store.frameSize = preset.size
                        }
                    }
                    Button("None") { store.frameSize = nil }
                } label: {
                    Text(frameLabel).font(Token.Text.value)
                }
                .menuStyle(.borderlessButton)
                .fixedSize())
            },
            RowSpec(id: "guides", glyph: "ruler", label: "Guides") {
                AnyView(Toggle("", isOn: $store.snapping)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden())
            }
        ]
    }

    private var frameLabel: String {
        guard let size = store.frameSize else { return "None" }
        return FramePreset.all.first { $0.size == size }?.name ?? "Custom"
    }
}

// MARK: - Row vocabulary

private struct RowSpec: Identifiable {
    let id: String
    let glyph: String
    let label: String
    var value: String? = nil
    let content: () -> AnyView
}

private struct Row: View {
    let spec: RowSpec
    let isLast: Bool

    private var leadingInset: CGFloat {
        Token.Size.separatorInset + 13 + Token.Space.lg
    }

    var body: some View {
        HStack(spacing: Token.Space.lg) {
            Image(systemName: spec.glyph)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary.opacity(Token.Ink.tertiary))
                .frame(width: 13)
            Text(spec.label)
                .font(Token.Text.label)
                .foregroundStyle(.primary.opacity(Token.Ink.secondary))
                .lineLimit(1)
                .fixedSize()
            Spacer(minLength: Token.Space.md)
            if let value = spec.value {
                Text(value)
                    .font(Token.Text.value)
                    .monospacedDigit()
                    .foregroundStyle(.primary.opacity(Token.Ink.tertiary))
                    .lineLimit(1)
                    .fixedSize()
            }
            spec.content()
        }
        .padding(.horizontal, Token.Size.separatorInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: Token.Size.row)
        .modifier(SeparatorIfNeeded(isLast: isLast, leadingInset: leadingInset))
    }
}

/// The last row never draws a hairline — that is what put a line on the panel's
/// bottom edge and made the rail look like it had been cut off.
private struct SeparatorIfNeeded: ViewModifier {
    let isLast: Bool
    let leadingInset: CGFloat

    func body(content: Content) -> some View {
        if isLast { content } else { content.rowSeparator(leadingInset: leadingInset) }
    }
}

private struct Swatches: View {
    let colors: [Color?]
    let names: [String]
    let selected: Int
    var size: CGFloat = Token.Size.swatch
    let action: (Int) -> Void

    var body: some View {
        HStack(spacing: Token.Space.sm + 1) {
            ForEach(colors.indices, id: \.self) { index in
                SwatchButton(color: colors[index],
                             help: names[index],
                             isActive: selected == index,
                             size: size) {
                    action(index)
                }
            }
        }
    }
}
