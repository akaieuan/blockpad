import SwiftUI
import AppKit

/// Shared surface treatment for every floating control. Everything in the app
/// that hovers over the canvas goes through this, so the chrome reads as one
/// material rather than a pile of separate widgets.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 14

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            content
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
    func glassSurface(cornerRadius: CGFloat = 14) -> some View {
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

// MARK: - Controls

/// Square icon button with a hover state and an optional shortcut badge.
struct ToolButton: View {
    let symbol: String
    let help: String
    var badge: String = ""
    var isActive: Bool = false
    var size: CGFloat = 32
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(background)
                Image(systemName: symbol)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(isActive ? Color(nsColor: Palette.selection) : .primary.opacity(0.82))
                if !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary.opacity(isActive ? 0.55 : 0.32))
                        .padding(.trailing, 3)
                        .padding(.bottom, 2)
                        .frame(width: size, height: size, alignment: .bottomTrailing)
                }
            }
            .frame(width: size, height: size)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: isActive)
    }

    private var background: Color {
        if isActive { return Color(nsColor: Palette.selection).opacity(0.16) }
        if hovering { return Color.primary.opacity(0.07) }
        return .clear
    }
}

/// A round colour chip. Used for stroke, fill and canvas background alike.
struct SwatchButton: View {
    let color: Color?
    let help: String
    let isActive: Bool
    var size: CGFloat = 18
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color ?? .clear)
                if color == nil {
                    // Transparent reads as a slash, not an empty hole.
                    Circle().strokeBorder(Color.primary.opacity(0.28), lineWidth: 1)
                    Path { path in
                        path.move(to: CGPoint(x: size * 0.24, y: size * 0.76))
                        path.addLine(to: CGPoint(x: size * 0.76, y: size * 0.24))
                    }
                    .stroke(Color(nsColor: Palette.colors[2]).opacity(0.85), lineWidth: 1.4)
                } else {
                    Circle().strokeBorder(Color.black.opacity(0.14), lineWidth: 1)
                }
                Circle()
                    .strokeBorder(Color(nsColor: Palette.selection), lineWidth: 2)
                    .padding(-3)
                    .opacity(isActive ? 1 : 0)
            }
            .frame(width: size, height: size)
            .scaleEffect(hovering && !isActive ? 1.12 : 1)
            .contentShape(Circle().inset(by: -3))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isActive)
    }
}

/// Labelled block in the properties panel.
struct PanelSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary.opacity(0.75))
                .tracking(0.6)
            content
        }
    }
}

/// Small segmented row of icon choices — fill style, corners, stroke weight.
struct IconSegments<T: Hashable>: View {
    let options: [(value: T, symbol: String, label: String)]
    let selected: T
    let action: (T) -> Void

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.value) { option in
                ToolButton(symbol: option.symbol,
                           help: option.label,
                           isActive: option.value == selected,
                           size: 27) {
                    action(option.value)
                }
            }
        }
    }
}

/// Icon button whose active state expands to show the tool's name. The morph is
/// the toolbar's signature: only one button is ever wide, so the bar reads as a
/// sentence about the current mode rather than a uniform grid of glyphs.
struct ToolPill: View {
    let symbol: String
    let label: String
    let help: String
    var isActive: Bool = false
    var showsLabel: Bool = true
    var size: CGFloat = 31
    let action: () -> Void

    @State private var hovering = false

    private var expanded: Bool { isActive && showsLabel }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 13.5, weight: .medium))
                if expanded {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .leading)))
                }
            }
            .foregroundStyle(isActive ? Color(nsColor: Palette.selection) : .primary.opacity(0.8))
            .padding(.horizontal, expanded ? 9 : 0)
            .frame(minWidth: size, minHeight: size)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(background)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: expanded)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var background: Color {
        if isActive { return Color(nsColor: Palette.selection).opacity(0.15) }
        if hovering { return Color.primary.opacity(0.07) }
        return .clear
    }
}

struct Divider1px: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(width: 1, height: 18)
            .padding(.horizontal, 3)
    }
}
