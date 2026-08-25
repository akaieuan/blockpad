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

    /// How many presets sit in the row itself. Four is what fits beside a label
    /// in a 172pt rail without the row wrapping.
    private static let inlineCount = 4

    var body: some View {
        HStack(spacing: 3.5) {
            if allowsNone {
                inlineChip(nil)
            }
            ForEach(presets.prefix(allowsNone ? Self.inlineCount - 1 : Self.inlineCount)) { preset in
                inlineChip(preset.hex, name: preset.name)
            }

            // Opens the full range: every preset, recents, RGB channels, hex.
            Button { open.toggle() } label: {
                ZStack {
                    swatch(current, size: 16, showsSelection: false)
                    // A ring only when the current colour is not one of the
                    // chips beside it, so the row shows where you actually are.
                    Circle()
                        .strokeBorder(Token.accent, lineWidth: 1.6)
                        .padding(-2.5)
                        .opacity(isCustom ? 1 : 0)
                }
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: Token.Radius.micro, style: .continuous)
                        .fill(hovering || open ? Color.primary.opacity(Token.Ink.hover) : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help("\(current ?? "No fill") — more colours")
            .popover(isPresented: $open, arrowEdge: .leading) { picker }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    /// True when the colour came from the picker rather than a visible chip.
    private var isCustom: Bool {
        let inline = presets.prefix(allowsNone ? Self.inlineCount - 1 : Self.inlineCount).map(\.hex)
        if current == nil { return !allowsNone }
        return !inline.contains(current!)
    }

    private func inlineChip(_ hex: String?, name: String? = nil) -> some View {
        Button {
            onChange(hex)
            hexField = hex ?? ""
        } label: {
            swatch(hex, size: 12)
                .frame(width: 15, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(name ?? hex ?? "None")
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

            section("Channels") {
                VStack(spacing: Token.Space.md) {
                    ChannelSlider(label: "R", value: channels.r, channel: .red,
                                  base: channels) { onChange(hex(replacing: .red, with: $0)) }
                    ChannelSlider(label: "G", value: channels.g, channel: .green,
                                  base: channels) { onChange(hex(replacing: .green, with: $0)) }
                    ChannelSlider(label: "B", value: channels.b, channel: .blue,
                                  base: channels) { onChange(hex(replacing: .blue, with: $0)) }
                }
            }

            section("Hex") {
                HStack(spacing: Token.Space.md) {
                    TextField("#RRGGBB", text: $hexField)
                        .textFieldStyle(.roundedBorder)
                        .font(Token.Text.value)
                        .onSubmit {
                            // Accepts #RGB, #RRGGBB, with or without the hash;
                            // silently ignores anything that is not a colour.
                            if let normalized = HexColor.normalized(hexField) {
                                onChange(normalized)
                            }
                        }

                    // The system panel stays available for eyedropper and the
                    // colour spaces this popover does not try to reproduce.
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
                }
            }
        }
        .padding(Token.Space.xl)
        .frame(width: 244)
        .onAppear { hexField = current ?? "" }
        // Keeps the field honest when the colour changes from a swatch or a
        // channel drag rather than from typing.
        .onChange(of: current) { _, newValue in hexField = newValue ?? "" }
    }

    /// Current colour as 0...255 components, falling back to the default so the
    /// channel sliders still have something to show when there is no fill.
    private var channels: (r: Double, g: Double, b: Double) {
        let c = HexColor.components(current ?? Palette.defaultStroke)
            ?? (r: 0, g: 0, b: 0, a: 1)
        return (c.r * 255, c.g * 255, c.b * 255)
    }

    private func hex(replacing channel: RGBChannel, with value: Double) -> String {
        var (r, g, b) = channels
        switch channel {
        case .red: r = value
        case .green: g = value
        case .blue: b = value
        }
        return HexColor.string(r: r / 255, g: g / 255, b: b / 255)
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

    private func swatch(_ hex: String?, size: CGFloat, showsSelection: Bool = true) -> some View {
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
                .opacity(showsSelection && hex == current ? 1 : 0)
        }
        .frame(width: size, height: size)
    }
}

enum RGBChannel { case red, green, blue }

/// One channel: a gradient track showing what the colour becomes as you drag,
/// plus a 0–255 field for when you know the number you want.
private struct ChannelSlider: View {
    let label: String
    let value: Double
    let channel: RGBChannel
    let base: (r: Double, g: Double, b: Double)
    let onChange: (Double) -> Void

    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Token.Space.lg) {
            Text(label)
                .font(Token.Text.micro)
                .foregroundStyle(.primary.opacity(Token.Ink.secondary))
                .frame(width: 9, alignment: .leading)

            ZStack {
                // The track previews the result, so you can aim rather than
                // guess — the whole reason to have channels and not just hex.
                Capsule()
                    .fill(LinearGradient(colors: [endpoint(0), endpoint(255)],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 4)
                Slider(value: Binding(get: { value }, set: { onChange($0.rounded()) }),
                       in: 0...255)
                    .controlSize(.mini)
                    .opacity(0.85)
            }

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(Token.Text.value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
                .frame(width: 26)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(
                    RoundedRectangle(cornerRadius: Token.Radius.micro, style: .continuous)
                        .fill(Color.primary.opacity(Token.Ink.sunken))
                )
        }
        .onAppear { text = String(Int(value)) }
        // Not while typing, or the field fights the keystrokes.
        .onChange(of: value) { _, newValue in
            if !focused { text = String(Int(newValue)) }
        }
    }

    private func commit() {
        guard let entered = Double(text.trimmingCharacters(in: .whitespaces)) else {
            text = String(Int(value))
            return
        }
        onChange(min(255, max(0, entered.rounded())))
    }

    private func endpoint(_ channelValue: Double) -> Color {
        var (r, g, b) = base
        switch channel {
        case .red: r = channelValue
        case .green: g = channelValue
        case .blue: b = channelValue
        }
        return Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255)
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
    /// Angles have no ends — scrubbing past 360 should come back round rather
    /// than stick.
    var wraps: Bool = false
    var unit: String = ""
    var presets: [Double] = []
    let onChange: (Double) -> Void

    @State private var hovering = false
    @State private var dragStart: Double?

    var body: some View {
        HStack(spacing: 1) {
            stepButton("minus", enabled: wraps || value > range.lowerBound) {
                onChange(bound(value - step))
            }

            // Drag horizontally to scrub, the way every design tool does it.
            Text(display)
                .font(Token.Text.value)
                .monospacedDigit()
                .foregroundStyle(.primary.opacity(Token.Ink.primary))
                .frame(width: 30, height: Token.Size.control)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { gesture in
                            if dragStart == nil { dragStart = value }
                            let delta = Double(gesture.translation.width) * step * 0.5
                            onChange(bound((dragStart ?? value) + delta))
                        }
                        .onEnded { _ in dragStart = nil }
                )
                .help("Drag to scrub")

            stepButton("plus", enabled: wraps || value < range.upperBound) {
                onChange(bound(value + step))
            }

            if !presets.isEmpty {
                Menu {
                    ForEach(presets, id: \.self) { preset in
                        Button(label(for: preset)) { onChange(bound(preset)) }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(.primary.opacity(Token.Ink.tertiary))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 13, height: Token.Size.control)
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
        if value >= 999 { return "Full" }
        let number = value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
        return number + unit
    }

    private func label(for preset: Double) -> String {
        preset >= 999 ? "Full (pill)" : (preset == preset.rounded() ? "\(Int(preset))" : String(format: "%.1f", preset))
    }

    private func clamp(_ next: Double) -> Double {
        min(max(next, range.lowerBound), range.upperBound)
    }

    /// Clamps, unless the value wraps — an angle has no ends, so scrubbing past
    /// 360 should come back round rather than stick at the top.
    private func bound(_ next: Double) -> Double {
        guard wraps else { return clamp(next) }
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return next }
        var wrapped = (next - range.lowerBound).truncatingRemainder(dividingBy: span)
        if wrapped < 0 { wrapped += span }
        return range.lowerBound + wrapped
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.primary.opacity(enabled ? Token.Ink.secondary : Token.Ink.tertiary * 0.5))
                .frame(width: 15, height: Token.Size.control)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
