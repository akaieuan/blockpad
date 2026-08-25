import SwiftUI

/// Small controls, all built from `Token` so they cannot drift apart again.

/// Square icon button. The workhorse: dock slots, zoom, row actions.
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
                RoundedRectangle(cornerRadius: Token.Radius.control, style: .continuous)
                    .fill(background)
                Image(systemName: symbol)
                    .font(.system(size: Token.Size.glyph, weight: .medium))
                    .foregroundStyle(isActive ? Token.accent : .primary.opacity(Token.Ink.primary))
                if !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.primary.opacity(isActive ? Token.Ink.secondary : Token.Ink.tertiary))
                        .padding([.trailing, .bottom], Token.Space.xs)
                        .frame(width: size, height: size, alignment: .bottomTrailing)
                }
            }
            .frame(width: size, height: size)
            .contentShape(RoundedRectangle(cornerRadius: Token.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: isActive)
    }

    private var background: Color {
        if isActive { return Token.accentSoft }
        if hovering { return Color.primary.opacity(Token.Ink.hover) }
        return .clear
    }
}

/// Icon button whose active state expands to name the tool. Only one is ever
/// wide, so the dock reads as a sentence about the current mode.
struct ToolPill: View {
    let symbol: String
    let label: String
    let help: String
    var isActive: Bool = false
    var showsLabel: Bool = true
    var size: CGFloat = 32
    let action: () -> Void

    @State private var hovering = false

    private var expanded: Bool { isActive && showsLabel }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Token.Space.md) {
                Image(systemName: symbol)
                    .font(.system(size: Token.Size.glyph, weight: .medium))
                if expanded {
                    Text(label)
                        .font(Token.Text.label)
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .leading)))
                }
            }
            .foregroundStyle(isActive ? Token.accent : .primary.opacity(Token.Ink.primary))
            .padding(.horizontal, expanded ? Token.Space.xl : 0)
            // A minimum width on the labelled state keeps the row from lurching
            // as the active tool's name changes length.
            .frame(minWidth: expanded ? Token.Dock.labelMinWidth : size, minHeight: size)
            .background(
                RoundedRectangle(cornerRadius: Token.Radius.control, style: .continuous)
                    .fill(background)
            )
            .contentShape(RoundedRectangle(cornerRadius: Token.Radius.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: expanded)
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var background: Color {
        if isActive { return Token.accentSoft }
        if hovering { return Color.primary.opacity(Token.Ink.hover) }
        return .clear
    }
}

/// Colour chip. Selection is a ring rather than a fill, so a chip never changes
/// its own colour to say it is chosen.
struct SwatchButton: View {
    let color: Color?
    let help: String
    let isActive: Bool
    var size: CGFloat = Token.Size.swatch
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(color ?? .clear)
                Circle().strokeBorder(Color.primary.opacity(color == nil ? 0.22 : 0.14), lineWidth: 1)
                if color == nil {
                    // Transparent reads as a slash, not an empty hole.
                    Path { path in
                        path.move(to: CGPoint(x: size * 0.26, y: size * 0.74))
                        path.addLine(to: CGPoint(x: size * 0.74, y: size * 0.26))
                    }
                    .stroke(Color(nsColor: Palette.color("#B4534A")).opacity(0.9), lineWidth: 1.3)
                }
                Circle()
                    .strokeBorder(Token.accent, lineWidth: 1.8)
                    .padding(-2.5)
                    .opacity(isActive ? 1 : 0)
            }
            .frame(width: size, height: size)
            .scaleEffect(hovering && !isActive ? 1.14 : 1)
            .contentShape(Circle().inset(by: -3))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.spring(response: 0.22, dampingFraction: 0.7), value: isActive)
    }
}

/// Segmented control sized for a row. Selection is a soft accent plate — never
/// a solid block, which is what made the old fill-style row shout.
struct Segments<Content: View>: View {
    let count: Int
    let selected: Int
    let names: [String]
    @ViewBuilder var glyph: (Int) -> Content
    let action: (Int) -> Void

    var body: some View {
        HStack(spacing: 1) {
            ForEach(0..<count, id: \.self) { index in
                Button { action(index) } label: {
                    glyph(index)
                        .foregroundStyle(selected == index ? Token.accent : .primary.opacity(Token.Ink.secondary))
                        .frame(width: 23, height: Token.Size.control)
                        .background(
                            RoundedRectangle(cornerRadius: Token.Radius.micro, style: .continuous)
                                .fill(selected == index ? Token.accentSoft : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(index < names.count ? names[index] : "")
            }
        }
        .padding(1.5)
        .background(
            RoundedRectangle(cornerRadius: Token.Radius.control, style: .continuous)
                .fill(Color.primary.opacity(Token.Ink.sunken))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Token.Radius.control, style: .continuous)
                .strokeBorder(Color.primary.opacity(Token.Ink.hairline), lineWidth: 1)
        )
    }
}

/// Compact action button for row-trailing clusters.
struct MiniButton: View {
    let symbol: String
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.primary.opacity(Token.Ink.primary))
                .frame(width: 22, height: Token.Size.control)
                .background(
                    RoundedRectangle(cornerRadius: Token.Radius.micro, style: .continuous)
                        .fill(hovering ? Color.primary.opacity(Token.Ink.hover) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
        .animation(.easeOut(duration: 0.1), value: hovering)
    }
}

// MARK: - Drawn glyphs

/// Drawn rather than SF Symbols so weight and size stay consistent across the
/// row — mixing `square.fill` with a stroked square is what looked broken.

struct WeightGlyph: View {
    let level: Int

    var body: some View {
        VStack(spacing: 2) {
            ForEach(0...level, id: \.self) { _ in
                Capsule().frame(width: 11, height: 1 + CGFloat(level) * 0.35)
            }
        }
        .frame(height: 11)
    }
}

struct CornerGlyph: View {
    let rounded: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: rounded ? 4 : 0.5, style: .continuous)
            .strokeBorder(lineWidth: 1.3)
            .frame(width: 11, height: 11)
    }
}

struct FillGlyph: View {
    let style: FillStyle

    var body: some View {
        ZStack {
            switch style {
            case .none:
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.1, dash: [2, 1.6]))
            case .hachure:
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(lineWidth: 1.1)
                Path { path in
                    for offset in stride(from: CGFloat(-8), through: 11, by: 3.6) {
                        path.move(to: CGPoint(x: offset, y: 11))
                        path.addLine(to: CGPoint(x: offset + 11, y: 0))
                    }
                }
                .stroke(lineWidth: 0.9)
                .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            case .solid:
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .strokeBorder(lineWidth: 1.1)
                RoundedRectangle(cornerRadius: 1.4, style: .continuous)
                    .padding(2)
                    .opacity(0.55)
            }
        }
        .frame(width: 11, height: 11)
    }
}

struct RenderGlyph: View {
    let sketchy: Bool

    var body: some View {
        Group {
            if sketchy {
                Image(systemName: "scribble.variable")
                    .font(.system(size: 10, weight: .medium))
            } else {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(lineWidth: 1.3)
                    .frame(width: 11, height: 11)
            }
        }
    }
}

/// A hairline between clusters of controls.
///
/// Sized from the row it sits in and inset top and bottom, rather than a fixed
/// 18pt that happened to look right at one button size. A separator running the
/// full height of its container is the same "unfinished" tell as one running
/// into a rounded corner.
struct Divider1px: View {
    var height: CGFloat = 18
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(Token.Ink.hairline + 0.03))
            .frame(width: 1, height: max(1, height - inset * 2))
    }
}
