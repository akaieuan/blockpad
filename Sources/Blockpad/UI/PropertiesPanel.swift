import SwiftUI

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
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)
        }
        .padding(.bottom, Token.Space.md)
        .frame(width: width, alignment: .leading)
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
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
            AnyView(Swatches(colors: Palette.colors.map { Color(nsColor: $0) },
                             names: Palette.names,
                             selected: style.colorIndex) { index in
                store.style.colorIndex = index
                canvas()?.applyStyle({ $0.colorIndex = index }, name: "Stroke Colour")
            })
        })

        rows.append(RowSpec(id: "weight", glyph: "lineweight", label: "Weight") {
            AnyView(Segments(count: StrokeWeight.names.count,
                             selected: style.strokeIndex,
                             names: StrokeWeight.names) { index in
                WeightGlyph(level: index)
            } action: { index in
                store.style.strokeIndex = index
                canvas()?.applyStyle({ $0.strokeIndex = index }, name: "Stroke Width")
            })
        })

        if showsFill {
            rows.append(RowSpec(id: "fill", glyph: "paintbrush", label: "Fill") {
                AnyView(Swatches(colors: Palette.fills.map { $0.map { Color(nsColor: $0) } },
                                 names: Palette.fillNames,
                                 selected: style.fillIndex) { index in
                    store.style.fillIndex = index
                    canvas()?.applyStyle({ block in
                        guard block.kind.takesFill else { return }
                        block.fillIndex = index
                        // Picking a colour while the style is none is a request
                        // to see it, not a no-op.
                        if index > 0, block.fillStyle == .none { block.fillStyle = .solid }
                    }, name: "Fill")
                })
            })

            if style.fillIndex > 0 {
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

            rows.append(RowSpec(id: "corners", glyph: "app.dashed", label: "Corners") {
                AnyView(Segments(count: CornerStyle.allCases.count,
                                 selected: CornerStyle.allCases.firstIndex(of: style.corner) ?? 0,
                                 names: CornerStyle.allCases.map(\.label)) { index in
                    CornerGlyph(rounded: CornerStyle.allCases[index] == .round)
                } action: { index in
                    let value = CornerStyle.allCases[index]
                    store.style.corner = value
                    canvas()?.applyStyle({ $0.corner = value }, name: "Edges")
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
            .frame(width: 68))
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
            }
            spec.content()
        }
        .padding(.horizontal, Token.Size.separatorInset)
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
