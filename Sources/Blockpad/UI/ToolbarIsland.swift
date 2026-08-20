import SwiftUI

/// Copy control, top right. The payload mode lives in the chevron (§5).
struct SendIsland: View {
    @ObservedObject var store: SketchStore
    @AppStorage("payloadMode") private var payloadModeRaw: String = PayloadMode.tree.rawValue
    var showsLabel: Bool = true
    var onSend: () -> Void

    @State private var hovering = false

    private var mode: PayloadMode { PayloadMode(rawValue: payloadModeRaw) ?? .tree }

    var body: some View {
        HStack(spacing: 2) {
            Button(action: onSend) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: 12, weight: .medium))
                    if showsLabel {
                        Text("Copy")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                }
                .padding(.horizontal, showsLabel ? 10 : 7)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(hovering ? Color.primary.opacity(0.07) : .clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("Copy payload   ⌘↩")

            Menu {
                Section("Payload") {
                    ForEach(PayloadMode.allCases) { option in
                        Button {
                            payloadModeRaw = option.rawValue
                        } label: {
                            if mode == option {
                                Label("\(option.label) · \(option.detail)", systemImage: "checkmark")
                            } else {
                                Text("\(option.label) · \(option.detail)")
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.6))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 18, height: 30)
            .help("Payload mode — currently \(mode.label)")
        }
        .padding(5)
        .glassSurface()
    }
}

/// Zoom and history, bottom left. Kept away from the tools so the two never
/// compete for the same corner of muscle memory.
struct BottomControls: View {
    @ObservedObject var store: SketchStore
    var canvas: () -> CanvasView?

    @State private var zoomLabel: String = "100%"

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 1) {
                ToolButton(symbol: "minus", help: "Zoom out", size: 28) {
                    canvas()?.setZoom(store.zoom * 0.8); refresh()
                }
                Button {
                    canvas()?.setZoom(1); refresh()
                } label: {
                    Text(zoomLabel)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .frame(width: 46, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reset zoom   ⌘0")

                ToolButton(symbol: "plus", help: "Zoom in", size: 28) {
                    canvas()?.setZoom(store.zoom * 1.25); refresh()
                }
            }
            .padding(4)
            .glassSurface(cornerRadius: 11)

            HStack(spacing: 1) {
                ToolButton(symbol: "arrow.uturn.backward", help: "Undo   ⌘Z", size: 28) {
                    canvas()?.undo()
                }
                ToolButton(symbol: "arrow.uturn.forward", help: "Redo   ⇧⌘Z", size: 28) {
                    canvas()?.redo()
                }
                ToolButton(symbol: "arrow.up.left.and.arrow.down.right", help: "Zoom to fit   ⌘9", size: 28) {
                    canvas()?.zoomToFit(); refresh()
                }
            }
            .padding(4)
            .glassSurface(cornerRadius: 11)
        }
        .onAppear(perform: refresh)
        .onReceive(Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()) { _ in
            refresh()
        }
    }

    /// Zoom lives on the AppKit side and changes during drags, so the label is
    /// polled rather than bound — cheaper than republishing on every scroll tick.
    private func refresh() {
        let next = "\(Int((store.zoom * 100).rounded()))%"
        if next != zoomLabel { zoomLabel = next }
    }
}
