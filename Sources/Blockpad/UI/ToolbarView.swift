import SwiftUI

/// One top bar. Five controls, nothing else (§3).
struct ToolbarView: View {
    @ObservedObject var store: SketchStore
    @AppStorage("payloadMode") private var payloadModeRaw: String = PayloadMode.tree.rawValue

    var onSend: () -> Void
    var onStrokeChange: (Int) -> Void

    private var payloadMode: PayloadMode {
        PayloadMode(rawValue: payloadModeRaw) ?? .tree
    }

    var body: some View {
        HStack(spacing: 10) {
            shapeMenu
            Divider().frame(height: 16)
            swatches
            Divider().frame(height: 16)
            strokeMenu
            frameMenu

            Spacer(minLength: 8)

            sendControl
        }
        .padding(.leading, 78) // clear the traffic lights
        .padding(.trailing, 12)
        .frame(height: 44)
        .background(VisualEffect(material: .headerView, blending: .withinWindow))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color.black.opacity(0.08)).frame(height: 1)
        }
    }

    // MARK: - Controls

    private var shapeMenu: some View {
        Menu {
            Button {
                store.tool = .select
            } label: {
                Label("Select   V", systemImage: "cursorarrow")
            }
            Divider()
            ForEach(BlockKind.allCases.filter(\.isAvailable), id: \.self) { kind in
                Button {
                    store.tool = .draw(kind)
                } label: {
                    Label("\(kind.label)   \(kind.shortcut)", systemImage: kind.symbol)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: store.tool.kind?.symbol ?? "cursorarrow")
                Text(store.tool.kind?.label ?? "Select")
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Shape tool")
    }

    private var swatches: some View {
        HStack(spacing: 6) {
            ForEach(Palette.colors.indices, id: \.self) { i in
                Button {
                    store.colorIndex = i
                    applyColorToSelection(i)
                } label: {
                    Circle()
                        .fill(Color(nsColor: Palette.color(i)))
                        .frame(width: 14, height: 14)
                        .overlay(
                            Circle()
                                .strokeBorder(Color.primary.opacity(store.colorIndex == i ? 0.85 : 0.12),
                                              lineWidth: store.colorIndex == i ? 2 : 1)
                        )
                }
                .buttonStyle(.plain)
                .help("\(Palette.name(i))   \(i + 1)")
            }
        }
    }

    private var strokeMenu: some View {
        Menu {
            ForEach(StrokeWeight.widths.indices, id: \.self) { i in
                Button {
                    store.strokeIndex = i
                    onStrokeChange(i)
                } label: {
                    if store.strokeIndex == i {
                        Label(StrokeWeight.names[i], systemImage: "checkmark")
                    } else {
                        Text(StrokeWeight.names[i])
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "lineweight")
                Text(StrokeWeight.names[store.strokeIndex])
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Stroke weight")
    }

    private var frameMenu: some View {
        Menu {
            ForEach(FramePreset.all) { preset in
                Button {
                    store.frameSize = preset.size
                } label: {
                    Text("\(preset.name)   \(Int(preset.size.width))×\(Int(preset.size.height))")
                }
            }
            Divider()
            Button("None") { store.frameSize = nil }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "rectangle.dashed")
                Text(frameLabel)
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Reference frame")
    }

    private var frameLabel: String {
        guard let size = store.frameSize else { return "No frame" }
        return FramePreset.all.first { $0.size == size }?.name ?? "\(Int(size.width))×\(Int(size.height))"
    }

    private var sendControl: some View {
        HStack(spacing: 0) {
            Button(action: onSend) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.doc.on.clipboard")
                    Text("Copy")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .frame(height: 24)
            }
            .buttonStyle(.plain)
            .help("Copy payload   ⌘↩")

            Menu {
                ForEach(PayloadMode.allCases) { mode in
                    Button {
                        payloadModeRaw = mode.rawValue
                    } label: {
                        if payloadMode == mode {
                            Label("\(mode.label)  ·  \(mode.detail)", systemImage: "checkmark")
                        } else {
                            Text("\(mode.label)  ·  \(mode.detail)")
                        }
                    }
                }
            } label: {
                EmptyView()
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.visible)
            .frame(width: 14)
            .help("Payload mode")
        }
        .padding(.horizontal, 2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.07))
        )
    }

    private func applyColorToSelection(_ index: Int) {
        guard !store.selection.isEmpty else { return }
        for i in store.blocks.indices where store.selection.contains(store.blocks[i].id) {
            store.blocks[i].colorIndex = index
        }
    }
}

struct VisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}
