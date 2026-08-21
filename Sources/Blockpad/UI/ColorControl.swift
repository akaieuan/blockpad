import SwiftUI
import BlockpadKit

/// Colour as a swatch that opens a popover: presets, recents, a hex field, and
/// the system picker for everything else.
///
/// Reverses §3's "five swatches, no picker". The presets remain the fast path —
/// most sketches never leave them — but the range is no longer five.
struct ColorControl: View {
    let current: String?
    let presets: [ColorPreset]
    let recents: [String]
    var allowsNone: Bool = false
    let onChange: (String?) -> Void

    @State private var open = false
    @State private var hovering = false
    @State private var hexField = ""

    private let columns = [GridItem(.adaptive(minimum: 18), spacing: 6)]

    var body: some View {
        Button { open.toggle() } label: {
            swatch(current, size: 15)
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: Token.Radius.micro, style: .continuous)
                        .fill(hovering || open ? Color.primary.opacity(Token.Ink.hover) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(current ?? "No fill")
        .popover(isPresented: $open, arrowEdge: .leading) { picker }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    private var picker: some View {
        VStack(alignment: .leading, spacing: Token.Space.xl) {
            section("Presets") {
                LazyVGrid(columns: columns, alignment: .leading, spacing: Token.Space.md) {
                    if allowsNone {
                        chip(nil)
                    }
                    ForEach(presets) { preset in
                        chip(preset.hex, name: preset.name)
                    }
                }
            }

            if !recents.isEmpty {
                section("Recent") {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: Token.Space.md) {
                        ForEach(recents, id: \.self) { hex in
                            chip(hex)
                        }
                    }
                }
            }

            section("Custom") {
                HStack(spacing: Token.Space.md) {
                    // The system picker covers everything the presets do not.
                    ColorPicker("", selection: Binding(
                        get: { Color(nsColor: Palette.color(current ?? Palette.defaultStroke)) },
                        set: { newValue in
                            guard let srgb = NSColor(newValue).usingColorSpace(.sRGB) else { return }
                            onChange(HexColor.string(r: srgb.redComponent,
                                                     g: srgb.greenComponent,
                                                     b: srgb.blueComponent))
                        }
                    ), supportsOpacity: false)
                    .labelsHidden()

                    TextField("#RRGGBB", text: $hexField)
                        .textFieldStyle(.roundedBorder)
                        .font(Token.Text.value)
                        .frame(width: 92)
                        .onSubmit {
                            // Accepts #RGB, #RRGGBB, with or without the hash;
                            // silently ignores anything that is not a colour.
                            if let normalized = HexColor.normalized(hexField) {
                                onChange(normalized)
                            }
                        }
                }
            }
        }
        .padding(Token.Space.xl)
        .frame(width: 208)
        .onAppear { hexField = current ?? "" }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Token.Space.lg) {
            Text(title)
                .font(Token.Text.micro)
                .foregroundStyle(.primary.opacity(Token.Ink.tertiary))
            content()
        }
    }

    private func chip(_ hex: String?, name: String? = nil) -> some View {
        Button {
            onChange(hex)
            hexField = hex ?? ""
        } label: {
            swatch(hex, size: 18)
        }
        .buttonStyle(.plain)
        .help(name ?? hex ?? "None")
    }

    private func swatch(_ hex: String?, size: CGFloat) -> some View {
        ZStack {
            Circle().fill(hex.map { Color(nsColor: Palette.color($0)) } ?? .clear)
            Circle().strokeBorder(Color.primary.opacity(hex == nil ? 0.22 : 0.14), lineWidth: 1)
            if hex == nil {
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
                .opacity(hex == current ? 1 : 0)
        }
        .frame(width: size, height: size)
    }
}

/// A number you can drag, step, or type. Presets live behind a right-click.
///
/// Stroke width and corner radius used to be three-way and two-way pickers.
/// Real values need real numbers — 1.5pt hairlines and 24pt radii both exist.
struct NumberControl: View {
    let value: Double
    let range: ClosedRange<Double>
    let step: Double
    var presets: [Double] = []
    let onChange: (Double) -> Void

    @State private var hovering = false
    @State private var dragStart: Double?

    var body: some View {
        HStack(spacing: 1) {
            stepButton("minus", enabled: value > range.lowerBound) {
                onChange(clamp(value - step))
            }

            // Drag horizontally to scrub, the way every design tool does it.
            Text(display)
                .font(Token.Text.value)
                .monospacedDigit()
                .foregroundStyle(.primary.opacity(Token.Ink.primary))
                .frame(width: 34, height: Token.Size.control)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { gesture in
                            if dragStart == nil { dragStart = value }
                            let delta = Double(gesture.translation.width) * step * 0.5
                            onChange(clamp((dragStart ?? value) + delta))
                        }
                        .onEnded { _ in dragStart = nil }
                )
                .help("Drag to scrub")

            stepButton("plus", enabled: value < range.upperBound) {
                onChange(clamp(value + step))
            }

            if !presets.isEmpty {
                Menu {
                    ForEach(presets, id: \.self) { preset in
                        Button(label(for: preset)) { onChange(clamp(preset)) }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.primary.opacity(Token.Ink.tertiary))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 14, height: Token.Size.control)
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

    private var display: String {
        value >= 999 ? "Full" : (value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value))
    }

    private func label(for preset: Double) -> String {
        preset >= 999 ? "Full (pill)" : (preset == preset.rounded() ? "\(Int(preset))" : String(format: "%.1f", preset))
    }

    private func clamp(_ next: Double) -> Double {
        min(max(next, range.lowerBound), range.upperBound)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.primary.opacity(enabled ? Token.Ink.secondary : Token.Ink.tertiary * 0.5))
                .frame(width: 16, height: Token.Size.control)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
