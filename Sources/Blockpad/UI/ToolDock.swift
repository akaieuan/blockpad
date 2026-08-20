import SwiftUI

/// Tools live in a dock along the bottom, not an island across the top.
///
/// Two reasons, one practical and one about identity. The top edge of a drawing
/// is where you look, so keeping it clear is worth more than the conventional
/// toolbar position. And eleven equal icons in a rounded pill at top centre is
/// somebody else's signature; this needs its own.
///
/// The dock shows seven controls, not eleven: shapes and connectors collapse
/// into one button each, holding the last one you used and offering the rest on
/// a flyout. That is the §3 rule — if a control is not in the bar it does not
/// exist — applied honestly.
struct ToolDock: View {
    @ObservedObject var store: SketchStore
    var buttonSize: CGFloat = 34
    var showsActiveLabel: Bool = true

    /// Remembers which member of each group was last used, so the collapsed
    /// button is never a surprise.
    @State private var lastShape: String = "box"
    @State private var lastConnector: String = "arrow"

    private func spec(_ id: String) -> ToolSpec {
        ToolSpec.all.first { $0.id == id } ?? ToolSpec.all[0]
    }

    var body: some View {
        HStack(spacing: Token.Space.xs) {
            pill(spec("select"))
            pill(spec("hand"))

            Divider1px()

            ToolGroupButton(specs: ToolSpec.shapes,
                            currentID: $lastShape,
                            store: store,
                            buttonSize: buttonSize,
                            showsActiveLabel: showsActiveLabel)
            ToolGroupButton(specs: ToolSpec.connectors,
                            currentID: $lastConnector,
                            store: store,
                            buttonSize: buttonSize,
                            showsActiveLabel: showsActiveLabel)
            pill(spec("pen"))
            pill(spec("text"))

            Divider1px()

            pill(spec("eraser"))
            ToolButton(symbol: "square.grid.2x2",
                       help: "Components",
                       isActive: store.libraryOpen,
                       size: buttonSize) {
                store.libraryOpen.toggle()
            }
            canvasMenu
        }
        .padding(Token.Space.md)
        .glassSurface(cornerRadius: Token.Radius.dock)
    }

    private func pill(_ spec: ToolSpec) -> some View {
        ToolPill(symbol: spec.symbol,
                 label: spec.label,
                 help: help(for: spec),
                 isActive: store.tool == spec.tool,
                 showsLabel: showsActiveLabel,
                 size: buttonSize) {
            store.tool = spec.tool
        }
    }

    private func help(for spec: ToolSpec) -> String {
        spec.digit.isEmpty ? "\(spec.label)   \(spec.key.uppercased())"
                           : "\(spec.label)   \(spec.key.uppercased()) or \(spec.digit)"
    }

    /// Canvas-level settings are not per-shape, so they belong behind one
    /// control rather than as a permanent block of a properties panel.
    private var canvasMenu: some View {
        Menu {
            Section("Canvas") {
                ForEach(CanvasTheme.all) { theme in
                    Button {
                        store.theme = theme
                    } label: {
                        if store.theme == theme {
                            Label(theme.name, systemImage: "checkmark")
                        } else {
                            Text(theme.name)
                        }
                    }
                }
            }
            Section("Render") {
                Button { store.sketchy = false } label: {
                    if store.sketchy { Text("Crisp") } else { Label("Crisp", systemImage: "checkmark") }
                }
                Button { store.sketchy = true } label: {
                    if store.sketchy { Label("Sketch", systemImage: "checkmark") } else { Text("Sketch") }
                }
            }
            Section("Reference frame") {
                ForEach(FramePreset.all) { preset in
                    Button {
                        store.frameSize = preset.size
                    } label: {
                        if store.frameSize == preset.size {
                            Label("\(preset.name)  \(Int(preset.size.width))×\(Int(preset.size.height))",
                                  systemImage: "checkmark")
                        } else {
                            Text("\(preset.name)  \(Int(preset.size.width))×\(Int(preset.size.height))")
                        }
                    }
                }
                Button("None") { store.frameSize = nil }
            }
            Divider()
            Button("Zoom to Fit") { CanvasHost.shared?.zoomToFit() }
            Button("Clear Canvas") { CanvasHost.shared?.clearAll() }
        } label: {
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: Token.Size.glyph, weight: .medium))
                .foregroundStyle(.primary.opacity(Token.Ink.primary))
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: buttonSize, height: buttonSize)
        .help("Canvas")
    }
}

/// One dock slot standing in for a family of tools. Click uses the current
/// member; the chevron swaps which member that is.
private struct ToolGroupButton: View {
    let specs: [ToolSpec]
    @Binding var currentID: String
    @ObservedObject var store: SketchStore
    var buttonSize: CGFloat
    var showsActiveLabel: Bool

    @State private var hovering = false

    private var current: ToolSpec {
        specs.first { $0.id == currentID } ?? specs[0]
    }

    private var isActive: Bool {
        specs.contains { $0.tool == store.tool }
    }

    var body: some View {
        HStack(spacing: 0) {
            ToolPill(symbol: activeSpec.symbol,
                     label: activeSpec.label,
                     help: "\(activeSpec.label)   \(activeSpec.key.uppercased())",
                     isActive: isActive,
                     showsLabel: showsActiveLabel,
                     size: buttonSize) {
                currentID = activeSpec.id
                store.tool = activeSpec.tool
            }

            Menu {
                ForEach(specs) { spec in
                    Button {
                        currentID = spec.id
                        store.tool = spec.tool
                    } label: {
                        if store.tool == spec.tool {
                            Label("\(spec.label)   \(spec.key.uppercased())", systemImage: "checkmark")
                        } else {
                            Text("\(spec.label)   \(spec.key.uppercased())")
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(.primary.opacity(hovering || isActive ? Token.Ink.secondary : Token.Ink.tertiary))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 12, height: buttonSize)
            .help("More \(specs.first?.groupName ?? "tools")")
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    /// If the live tool belongs to this group, the button shows that rather than
    /// the remembered one — otherwise a keyboard shortcut could select a tool
    /// the dock does not appear to have.
    private var activeSpec: ToolSpec {
        specs.first { $0.tool == store.tool } ?? current
    }
}
