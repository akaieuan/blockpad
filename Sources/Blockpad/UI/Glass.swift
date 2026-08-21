import SwiftUI
import AppKit

/// Shared surface treatment for every floating control. Everything in the app
/// that hovers over the canvas goes through this, so the chrome reads as one
/// material rather than a pile of separate widgets.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = Token.Radius.panel

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .background(
                    VisualEffect(material: .popover, blending: .withinWindow)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.55), lineWidth: 1)
                        .blendMode(.overlay)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.black.opacity(0.07), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.16), radius: 16, y: 5)
        }
    }
}

extension View {
    func glassSurface(cornerRadius: CGFloat = Token.Radius.panel) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius))
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
