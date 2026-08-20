import SwiftUI

/// The inspector rail.
///
/// Design language is rows, not blocks: a leading glyph, a quiet label, and the
/// control pushed to the trailing edge, separated by hairlines. Stacked
/// all-caps section headers over chunky icon grids is a look this app is
/// deliberately not wearing — and rows fit far more into a small floating
/// window, which is the shape this thing actually lives in.
struct PropertiesPanel: View {
    @ObservedObject var store: SketchStore
    var width: CGFloat = 186
    var canvas: () -> CanvasView?

    private var hasSelection: Bool { !store.selection.isEmpty }
    private var showsShapeProperties: Bool { hasSelection || store.tool.isDrawing }
    private var style: Style { store.effectiveStyle }

    /// Fill only means something for closed shapes, and offering it for an arrow
    /// is how an inspector starts feeling like a settings screen.
    private var showsFill: Bool {
        if hasSelection { return store.selectedBlocks.contains { $0.kind.takesFill } }
        return store.tool.kind?.takesFill ?? false
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if showsShapeProperties {
                Row(glyph: "scribble", label: "Stroke") {
                    Swatches(colors: Palette.colors.map { Color(nsColor: $0) },
                             names: Palette.names,
                             selected: style.colorIndex) { index in
                        store.style.colorIndex = index
                        canvas()?.applyStyle({ $0.colorIndex = index }, name: "Stroke Colour")
                    }
                }
                Row(glyph: "lineweight", label: "Weight") {
                    Segments(count: StrokeWeight.names.count,
                             selected: style.strokeIndex,
                             names: StrokeWeight.names) { index in
                        WeightGlyph(level: index)
                    } action: { index in
                        store.style.strokeIndex = index
                        canvas()?.applyStyle({ $0.strokeIndex = index }, name: "Stroke Width")
                    }
                }
                if showsFill {
                    Row(glyph: "paintbrush", label: "Fill") {
                        Swatches(colors: Palette.fills.map { $0.map { Color(nsColor: $0) } },
                                 names: Palette.fillNames,
                                 selected: style.fillIndex) { index in
                            store.style.fillIndex = index
                            canvas()?.applyStyle({ block in
                                guard block.kind.takesFill else { return }
                                block.fillIndex = index
                                // Picking a colour while the style is none is a
                                // request to see it, not a no-op.
                                if index > 0, block.fillStyle == .none { block.fillStyle = .solid }
                            }, name: "Fill")
                        }
                    }
                    if style.fillIndex > 0 {
                        Row(glyph: "square.on.square.dashed", label: "Pattern") {
                            Segments(count: FillStyle.allCases.count,
                                     selected: FillStyle.allCases.firstIndex(of: style.fillStyle) ?? 0,
                                     names: FillStyle.allCases.map(\.label)) { index in
                                Image(systemName: FillStyle.allCases[index].symbol)
                                    .font(.system(size: 10, weight: .medium))
                            } action: { index in
                                let value = FillStyle.allCases[index]
                                store.style.fillStyle = value
                                canvas()?.applyStyle({ $0.fillStyle = value }, name: "Fill Style")
                            }
                        }
                    }
                    Row(glyph: "app.dashed", label: "Corners") {
                        Segments(count: CornerStyle.allCases.count,
                                 selected: CornerStyle.allCases.firstIndex(of: style.corner) ?? 0,
                                 names: CornerStyle.allCases.map(\.label)) { index in
                            RoundedRectangle(cornerRadius: index == 1 ? 4 : 0, style: .continuous)
                                .strokeBorder(lineWidth: 1.4)
                                .frame(width: 11, height: 11)
                        } action: { index in
                            let value = CornerStyle.allCases[index]
                            store.style.corner = value
                            canvas()?.applyStyle({ $0.corner = value }, name: "Edges")
                        }
                    }
                }
                Row(glyph: "circle.lefthalf.filled", label: "Opacity", trailingText: "\(Int(style.opacity * 100))%") {
                    Slider(value: Binding(
                        get: { style.opacity },
                        set: { value in
                            store.style.opacity = value
                            canvas()?.applyStyle({ $0.opacity = value }, name: "Opacity")
                        }
                    ), in: 0.1...1)
                    .controlSize(.mini)
                    .frame(width: 78)
                }
                if hasSelection {
                    Row(glyph: "square.2.layers.3d", label: "Order") {
                        HStack(spacing: 2) {
                            MiniButton(symbol: "square.3.layers.3d.bottom.filled", help: "Send to back   ⇧⌘[") {
                                canvas()?.reorder(toFront: true, forward: false)
                            }
                            MiniButton(symbol: "arrow.down", help: "Send backward   ⌘[") {
                                canvas()?.reorder(toFront: false, forward: false)
                            }
                            MiniButton(symbol: "arrow.up", help: "Bring forward   ⌘]") {
                                canvas()?.reorder(toFront: false, forward: true)
                            }
                            MiniButton(symbol: "square.3.layers.3d.top.filled", help: "Bring to front   ⇧⌘]") {
                                canvas()?.reorder(toFront: true, forward: true)
                            }
                        }
                    }
                    Row(glyph: "hammer", label: "Edit") {
                        HStack(spacing: 2) {
                            MiniButton(symbol: "plus.square.on.square", help: "Duplicate   ⌘D") {
                                canvas()?.duplicateSelection()
                            }
                            MiniButton(symbol: "trash", help: "Delete   ⌫") {
                                canvas()?.deleteSelection()
                            }
                        }
                    }
                }
            } else {
                Row(glyph: "square.grid.3x3", label: "Canvas") {
                    Swatches(colors: CanvasTheme.all.map { Color(nsColor: $0.color) },
                             names: CanvasTheme.all.map(\.name),
                             selected: CanvasTheme.all.firstIndex(of: store.theme) ?? 0) { index in
                        store.theme = CanvasTheme.all[index]
                    }
                }
                Row(glyph: "pencil.and.outline", label: "Render") {
                    Segments(count: 2, selected: store.sketchy ? 1 : 0,
                             names: ["Crisp", "Sketch"]) { index in
                        Image(systemName: index == 0 ? "square.on.square.squareshape.controlhandles" : "scribble.variable")
                            .font(.system(size: 10, weight: .medium))
                    } action: { index in
                        store.sketchy = index == 1
                    }
                }
                Row(glyph: "rectangle.dashed", label: "Frame") {
                    Menu {
                        ForEach(FramePreset.all) { preset in
                            Button("\(preset.name)  \(Int(preset.size.width))×\(Int(preset.size.height))") {
                                store.frameSize = preset.size
                            }
                        }
                        Button("None") { store.frameSize = nil }
                    } label: {
                        Text(frameLabel)
                            .font(.system(size: 10.5, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                Row(glyph: "ruler", label: "Guides", trailingText: nil) {
                    Toggle("", isOn: $store.snapping)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                }
            }
        }
        .padding(.vertical, 3)
        .frame(width: width, alignment: .leading)
        .glassSurface()
        .animation(.easeOut(duration: 0.16), value: showsShapeProperties)
        .animation(.easeOut(duration: 0.16), value: showsFill)
        .animation(.easeOut(duration: 0.16), value: style.fillIndex > 0)
    }

    private var frameLabel: String {
        guard let size = store.frameSize else { return "None" }
        return FramePreset.all.first { $0.size == size }?.name ?? "Custom"
    }

    /// Names what the rail is currently talking about, which is the one piece of
    /// text worth spending vertical space on.
    private var header: some View {
        HStack(spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.55))
            Spacer()
            if hasSelection {
                Text("\(store.selection.count)")
                    .font(.system(size: 9, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Color(nsColor: Palette.selection))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule().fill(Color(nsColor: Palette.selection).opacity(0.14))
                    )
            }
        }
        .padding(.horizontal, 11)
        .padding(.top, 6)
        .padding(.bottom, 7)
    }

    private var title: String {
        if hasSelection {
            let kinds = Set(store.selectedBlocks.map(\.kind))
            return kinds.count == 1 ? (kinds.first?.label ?? "Selection") : "Selection"
        }
        if let kind = store.tool.kind { return kind.label }
        return "Canvas"
    }
}

// MARK: - Row vocabulary

/// Glyph, label, control — hairline below. Every line in the rail is this.
private struct Row<Content: View>: View {
    let glyph: String
    let label: String
    var trailingText: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: glyph)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.4))
                    .frame(width: 13)
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.62))
                    .lineLimit(1)
                    .fixedSize()
                Spacer(minLength: 6)
                if let trailingText {
                    Text(trailingText)
                        .font(.system(size: 9.5, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.primary.opacity(0.4))
                }
                content
            }
            .padding(.horizontal, 11)
            .frame(height: 30)

            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 1)
                .padding(.leading, 31)
        }
    }
}

private struct Swatches: View {
    let colors: [Color?]
    let names: [String]
    let selected: Int
    var size: CGFloat = 13
    let action: (Int) -> Void

    var body: some View {
        HStack(spacing: 4) {
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

/// Hairline-bordered segmented control, sized for a row rather than a panel.
private struct Segments<Content: View>: View {
    let count: Int
    let selected: Int
    let names: [String]
    @ViewBuilder var glyph: (Int) -> Content
    let action: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                Button { action(index) } label: {
                    glyph(index)
                        .foregroundStyle(selected == index
                                         ? Color(nsColor: Palette.selection)
                                         : .primary.opacity(0.55))
                        .frame(width: 22, height: 19)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(selected == index
                                      ? Color(nsColor: Palette.selection).opacity(0.15)
                                      : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(index < names.count ? names[index] : "")
            }
        }
        .padding(1.5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct WeightGlyph: View {
    let level: Int

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0...level, id: \.self) { _ in
                Capsule().frame(width: 11, height: 1.4)
            }
        }
        .frame(height: 11)
    }
}

private struct MiniButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary.opacity(0.7))
                .frame(width: 21, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hovering ? Color.primary.opacity(0.09) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .animation(.easeOut(duration: 0.1), value: hovering)
    }
}

/// Component library, opened from the dock. Click drops the preset into the
/// middle of the viewport already selected, so it can be dragged immediately.
struct LibraryPanel: View {
    @ObservedObject var store: SketchStore
    var canvas: () -> CanvasView?

    private let columns = [GridItem(.adaptive(minimum: 74), spacing: 7)]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("Components")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.55))
                Spacer()
                MiniButton(symbol: "xmark", help: "Close   Esc") {
                    store.libraryOpen = false
                }
            }
            LazyVGrid(columns: columns, spacing: 7) {
                ForEach(ComponentPreset.all) { preset in
                    LibraryTile(preset: preset) { canvas()?.insert(preset) }
                }
            }
        }
        .padding(11)
        .frame(width: 254)
        .glassSurface()
    }
}

private struct LibraryTile: View {
    let preset: ComponentPreset
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: preset.symbol)
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(.primary.opacity(0.75))
                    .frame(height: 20)
                Text(preset.name)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.65))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.09 : 0.045))
            )
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Insert \(preset.name)")
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
