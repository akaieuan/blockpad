import SwiftUI

struct RootView: View {
    @ObservedObject var store: SketchStore
    @AppStorage("payloadMode") private var payloadModeRaw: String = PayloadMode.tree.rawValue

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                ToolbarView(
                    store: store,
                    onSend: send,
                    onStrokeChange: { CanvasHost.shared?.applyStroke($0) }
                )
                CanvasRepresentable(store: store, onSend: send)
            }

            if let toast = store.toast {
                Text(toast)
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                            .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
                    )
                    .padding(.top, 56)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeOut(duration: 0.16), value: store.toast)
    }

    private func send() {
        let mode = PayloadMode(rawValue: payloadModeRaw) ?? .tree
        let result = SketchExport.copyToPasteboard(store.blocks, mode: mode)
        store.flash(result)
    }
}

/// Bridges the AppKit canvas into the SwiftUI tree (§7).
struct CanvasRepresentable: NSViewRepresentable {
    let store: SketchStore
    let onSend: () -> Void

    func makeNSView(context: Context) -> CanvasView {
        let view = CanvasView(store: store)
        view.onSend = onSend
        view.onCopy = onSend
        CanvasHost.shared = view
        return view
    }

    func updateNSView(_ view: CanvasView, context: Context) {
        view.onSend = onSend
        view.onCopy = onSend
    }
}

/// The toolbar needs to reach the canvas for operations that act on the
/// selection. One live canvas exists for the app's lifetime, so a reference is
/// simpler and less fragile than threading a binding through.
@MainActor
enum CanvasHost {
    static weak var shared: CanvasView?
}
