import SwiftUI

/// Left rail. Shows shape properties when there is something to style, and
/// canvas settings when there isn't, so the panel is never a column of dead
/// controls.
struct PropertiesPanel: View {
    @ObservedObject var store: SketchStore
    var width: CGFloat = 186
    var canvas: () -> CanvasView?

    private var hasSelection: Bool { !store.selection.isEmpty }
    private var showsShapeProperties: Bool { hasSelection || store.tool.isDrawing }
    private var style: Style { store.effectiveStyle }

    /// Fill only makes sense for closed shapes, and showing it for an arrow is
    /// how a properties panel starts feeling like a settings screen.
    private var showsFill: Bool {
        if hasSelection { return store.selectedBlocks.contains { $0.kind.takesFill } }
        return store.tool.kind?.takesFill ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsShapeProperties {
                strokeSection
                if showsFill { fillSection }
                strokeWidthSection
                cornerSection
                opacitySection
                if hasSelection { layerSection; actionSection }
            } else {
                canvasSection
            }
        }
        .padding(11)
        .frame(width: width, alignment: .leading)
        .glassSurface()
        .animation(.easeOut(duration: 0.16), value: showsShapeProperties)
        .animation(.easeOut(duration: 0.16), value: showsFill)
    }

    // MARK: - Sections

    private var strokeSection: some View {
        PanelSection(title: "Stroke") {
            HStack(spacing: 8) {
                ForEach(Palette.colors.indices, id: \.self) { i in
                    SwatchButton(color: Color(nsColor: Palette.color(i)),
                                 help: "\(Palette.name(i))   \(i + 1)",
                                 isActive: style.colorIndex == i) {
                        store.style.colorIndex = i
                        canvas()?.applyStyle({ $0.colorIndex = i }, name: "Stroke Colour")
                    }
                }
            }
        }
    }

    private var fillSection: some View {
        PanelSection(title: "Fill") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ForEach(Palette.fills.indices, id: \.self) { i in
                        SwatchButton(color: Palette.fill(i).map { Color(nsColor: $0) },
                                     help: Palette.fillNames[i],
                                     isActive: style.fillIndex == i) {
                            store.style.fillIndex = i
                            canvas()?.applyStyle({ block in
                                guard block.kind.takesFill else { return }
                                block.fillIndex = i
                                // Picking a colour with the style set to none is
                                // a request to see it, not a no-op.
                                if i > 0, block.fillStyle == .none { block.fillStyle = .hachure }
                            }, name: "Fill")
                        }
                    }
                }
                if style.fillIndex > 0 {
                    IconSegments(options: FillStyle.allCases.map { ($0, $0.symbol, $0.label) },
                                 selected: style.fillStyle) { value in
                        store.style.fillStyle = value
                        canvas()?.applyStyle({ $0.fillStyle = value }, name: "Fill Style")
                    }
                }
            }
        }
    }

    private var strokeWidthSection: some View {
        PanelSection(title: "Stroke width") {
            IconSegments(options: [
                (0, "minus", "Thin"),
                (1, "equal", "Medium"),
                (2, "lineweight", "Bold")
            ], selected: style.strokeIndex) { value in
                store.style.strokeIndex = value
                canvas()?.applyStyle({ $0.strokeIndex = value }, name: "Stroke Width")
            }
        }
    }

    private var cornerSection: some View {
        PanelSection(title: "Edges") {
            IconSegments(options: CornerStyle.allCases.map { ($0, $0.symbol, $0.label) },
                         selected: style.corner) { value in
                store.style.corner = value
                canvas()?.applyStyle({ $0.corner = value }, name: "Edges")
            }
        }
    }

    private var opacitySection: some View {
        PanelSection(title: "Opacity") {
            Slider(value: Binding(
                get: { style.opacity },
                set: { value in
                    store.style.opacity = value
                    canvas()?.applyStyle({ $0.opacity = value }, name: "Opacity")
                }
            ), in: 0.1...1)
            .controlSize(.mini)
        }
    }

    private var layerSection: some View {
        PanelSection(title: "Layers") {
            HStack(spacing: 3) {
                ToolButton(symbol: "square.3.layers.3d.bottom.filled", help: "Send to back   ⇧⌘[", size: 27) {
                    canvas()?.reorder(toFront: true, forward: false)
                }
                ToolButton(symbol: "arrow.down.square", help: "Send backward   ⌘[", size: 27) {
                    canvas()?.reorder(toFront: false, forward: false)
                }
                ToolButton(symbol: "arrow.up.square", help: "Bring forward   ⌘]", size: 27) {
                    canvas()?.reorder(toFront: false, forward: true)
                }
                ToolButton(symbol: "square.3.layers.3d.top.filled", help: "Bring to front   ⇧⌘]", size: 27) {
                    canvas()?.reorder(toFront: true, forward: true)
                }
            }
        }
    }

    private var actionSection: some View {
        PanelSection(title: "Actions") {
            HStack(spacing: 3) {
                ToolButton(symbol: "plus.square.on.square", help: "Duplicate   ⌘D", size: 27) {
                    canvas()?.duplicateSelection()
                }
                ToolButton(symbol: "trash", help: "Delete   ⌫", size: 27) {
                    canvas()?.deleteSelection()
                }
            }
        }
    }

    private var canvasSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PanelSection(title: "Canvas") {
                HStack(spacing: 8) {
                    ForEach(CanvasTheme.all) { theme in
                        SwatchButton(color: Color(nsColor: theme.color),
                                     help: theme.name,
                                     isActive: store.theme == theme) {
                            store.theme = theme
                        }
                    }
                }
            }

            PanelSection(title: "Render") {
                IconSegments(options: [
                    (false, "square.on.square.squareshape.controlhandles", "Crisp"),
                    (true, "scribble.variable", "Sketch")
                ], selected: store.sketchy) { value in
                    store.sketchy = value
                }
            }

            PanelSection(title: "Reference frame") {
                Picker("", selection: Binding(
                    get: { store.frameSize.map { size in
                        FramePreset.all.first { $0.size == size }?.name ?? "Custom"
                    } ?? "None" },
                    set: { name in
                        store.frameSize = FramePreset.all.first { $0.name == name }?.size
                    }
                )) {
                    ForEach(FramePreset.all) { preset in
                        Text("\(preset.name)  \(Int(preset.size.width))×\(Int(preset.size.height))")
                            .tag(preset.name)
                    }
                    Text("None").tag("None")
                }
                .labelsHidden()
                .controlSize(.small)
            }

            PanelSection(title: "Actions") {
                HStack(spacing: 3) {
                    ToolButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Zoom to fit   ⌘9", size: 27) {
                        canvas()?.zoomToFit()
                    }
                    ToolButton(symbol: "trash", help: "Clear canvas   ⌘⌫", size: 27) {
                        canvas()?.clearAll()
                    }
                }
            }
        }
    }
}

/// Component library, opened from the toolbar. Click drops the preset into the
/// middle of the viewport already selected, so it can be dragged immediately.
struct LibraryPanel: View {
    @ObservedObject var store: SketchStore
    var canvas: () -> CanvasView?

    private let columns = [GridItem(.adaptive(minimum: 74), spacing: 8)]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("COMPONENTS")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary.opacity(0.75))
                    .tracking(0.6)
                Spacer()
                ToolButton(symbol: "xmark", help: "Close   Esc", size: 22) {
                    store.libraryOpen = false
                }
            }

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(ComponentPreset.all) { preset in
                    LibraryTile(preset: preset) { canvas()?.insert(preset) }
                }
            }
        }
        .padding(12)
        .frame(width: 258)
        .glassSurface()
    }
}

private struct LibraryTile: View {
    let preset: ComponentPreset
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: preset.symbol)
                    .font(.system(size: 17, weight: .light))
                    .foregroundStyle(.primary.opacity(0.75))
                    .frame(height: 22)
                Text(preset.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
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
