import SwiftUI
import BlockpadKit

// MARK: - The bind affordance

/// Binding lives on a property row's leading glyph rather than in a control of
/// its own.
///
/// A 172pt rail has no room for a second control on five rows, and a bound row
/// already names its variable in the value slot — so the affordance has to be
/// reachable, not loud. Bound turns the glyph accent, which is the same
/// vocabulary the rest of the chrome uses for "this is set".
struct BindGlyph: View {
    struct Model {
        let symbol: String
        let property: BoundProperty
        let boundTo: UUID?
        let candidates: [Variable]
        let mode: String
        /// What a new variable would be seeded from. nil disables creation —
        /// a mixed selection has no single value to name.
        let value: VariableValue?
        let suggestedName: String
        let onBind: (UUID?) -> Void
        let onCreate: (String, VariableValue) -> UUID?
    }

    let model: Model

    @State private var open = false
    @State private var hovering = false
    @State private var draft = ""

    private var isBound: Bool { model.boundTo != nil }

    var body: some View {
        Button {
            draft = model.suggestedName
            open.toggle()
        } label: {
            Image(systemName: model.symbol)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(isBound ? Token.accent : .primary.opacity(Token.Ink.tertiary))
                // The plate expands outside the glyph's own box, so making a row
                // bindable does not widen the rail by a single point.
                .frame(width: 13, height: 18)
                .background(
                    RoundedRectangle(cornerRadius: Token.Radius.micro, style: .continuous)
                        .fill(hovering || open ? Color.primary.opacity(Token.Ink.hover) : .clear)
                        .padding(.horizontal, -3)
                )
                .contentShape(Rectangle().inset(by: -3))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(isBound ? "Bound — change or unbind" : "Bind \(model.property.label) to a variable")
        .popover(isPresented: $open, arrowEdge: .leading) {
            BindPicker(model: model, draft: $draft) { open = false }
        }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// The bind popover's contents, separate from the glyph that opens it so it can
/// be rendered offscreen rather than only reached by clicking.
struct BindPicker: View {
    let model: BindGlyph.Model
    @Binding var draft: String
    let dismiss: () -> Void

    private var isBound: Bool { model.boundTo != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: Token.Space.lg) {
            Text(model.property.label)
                .font(Token.Text.header)
                .foregroundStyle(.primary.opacity(Token.Ink.strong))

            if model.candidates.isEmpty {
                Text("No \(model.property.wantsColour ? "colour" : "number") variables yet")
                    .font(Token.Text.value)
                    .foregroundStyle(.primary.opacity(Token.Ink.tertiary))
            } else {
                VStack(spacing: 1) {
                    ForEach(model.candidates) { variable in
                        candidate(variable)
                    }
                }
            }

            Rectangle()
                .fill(Color.primary.opacity(Token.Ink.hairline))
                .frame(height: 1)

            HStack(spacing: Token.Space.md) {
                TextField("new name", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .font(Token.Text.value)
                    .onSubmit(create)
                Button(action: create) {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.value == nil ? .primary.opacity(Token.Ink.tertiary) : Token.accent)
                .disabled(model.value == nil)
                .help("Create and bind")
            }

            if isBound {
                Button { model.onBind(nil); dismiss() } label: {
                    Text("Unbind").font(Token.Text.value)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary.opacity(Token.Ink.secondary))
            }
        }
        .padding(Token.Space.xl)
        .frame(width: 178)
    }

    private func candidate(_ variable: Variable) -> some View {
        Button {
            model.onBind(variable.id)
            dismiss()
        } label: {
            HStack(spacing: Token.Space.md) {
                VariableChip(variable: variable, mode: model.mode)
                Text(variable.token)
                    .font(Token.Text.label)
                    .foregroundStyle(.primary.opacity(Token.Ink.primary))
                    .lineLimit(1)
                Spacer(minLength: Token.Space.sm)
                if model.boundTo == variable.id {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Token.accent)
                }
            }
            .padding(.horizontal, Token.Space.md)
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func create() {
        guard let value = model.value else { return }
        guard let id = model.onCreate(draft, value) else { return }
        model.onBind(id)
        dismiss()
    }
}

/// A variable's current value, small enough to sit beside its name. Colours read
/// as a swatch, numbers as the number — anything else would need a legend.
struct VariableChip: View {
    let variable: Variable
    let mode: String

    var body: some View {
        let value = variable.values[mode] ?? variable.values[variable.values.keys.sorted().first ?? mode]
        Group {
            if let hex = value?.colourHex {
                ZStack {
                    Circle().fill(Color(nsColor: Palette.color(hex)))
                    Circle().strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
                }
                .frame(width: Token.Size.swatch, height: Token.Size.swatch)
            } else {
                Text(value?.literal ?? "—")
                    .font(Token.Text.micro)
                    .monospacedDigit()
                    .foregroundStyle(.primary.opacity(Token.Ink.secondary))
                    .frame(width: Token.Size.swatch + 4)
            }
        }
    }
}

// MARK: - The manager

/// Create, rename, revalue and delete — plus the modes everything varies across.
///
/// A floating panel rather than a popover on the inspector row, because editing
/// a colour opens a popover of its own and popovers do not nest.
struct VariablesPanel: View {
    @ObservedObject var store: SketchStore
    var maxHeight: CGFloat = .infinity
    var canvas: () -> CanvasView? = { nil }

    @State private var draftName = ""
    @State private var modeDraft = ""
    @State private var addingMode = false

    private var modes: [String] { store.availableModes.isEmpty ? [store.mode] : store.availableModes }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            modeStrip
            list
            footer
        }
        .frame(width: 268)
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .glassSurface()
    }

    private var header: some View {
        HStack(spacing: Token.Space.md) {
            Text("Variables")
                .font(Token.Text.header)
                .foregroundStyle(.primary.opacity(Token.Ink.strong))
            Spacer()
            Text("\(store.variables.count)")
                .font(Token.Text.micro)
                .monospacedDigit()
                .foregroundStyle(.primary.opacity(Token.Ink.tertiary))
            MiniButton(symbol: "xmark", help: "Close") { store.variablesOpen = false }
        }
        .padding(.horizontal, Token.Size.separatorInset)
        .padding(.top, Token.Space.lg + 2)
        .padding(.bottom, Token.Space.lg)
    }

    /// The mode strip switches the canvas as well as this panel, deliberately:
    /// editing the dark palette while looking at the light drawing is how a dark
    /// theme ends up shipping broken.
    private var modeStrip: some View {
        HStack(spacing: Token.Space.md) {
            HStack(spacing: 1) {
                ForEach(modes, id: \.self) { name in
                    Button { store.mode = name } label: {
                        Text(name)
                            .font(Token.Text.value)
                            .lineLimit(1)
                            .foregroundStyle(store.mode == name
                                             ? Token.accent
                                             : .primary.opacity(Token.Ink.secondary))
                            .frame(maxWidth: .infinity)
                            .frame(height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: Token.Radius.micro, style: .continuous)
                                    .fill(store.mode == name ? Token.accentSoft : .clear)
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(modes.count > 1 ? "Show \(name)" : name)
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

            if addingMode {
                TextField("mode", text: $modeDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(Token.Text.value)
                    .frame(width: 62)
                    .onSubmit {
                        if store.addMode(modeDraft) { store.mode = modeDraft.trimmingCharacters(in: .whitespaces) }
                        modeDraft = ""
                        addingMode = false
                    }
            } else {
                MiniButton(symbol: "plus", help: "Add a mode") { addingMode = true }
                if modes.count > 1 {
                    MiniButton(symbol: "minus", help: "Remove \(store.mode)") {
                        store.removeMode(store.mode)
                    }
                }
            }
        }
        .padding(.horizontal, Token.Size.separatorInset)
        .padding(.bottom, Token.Space.md)
        .animation(.easeOut(duration: 0.14), value: addingMode)
    }

    @ViewBuilder
    private var list: some View {
        if store.variables.isEmpty {
            Text("A colour or a number, named once and used everywhere. The payload carries the name and the value.")
                .font(Token.Text.value)
                .foregroundStyle(.primary.opacity(Token.Ink.tertiary))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Token.Size.separatorInset)
                .padding(.vertical, Token.Space.lg)
        } else {
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(store.variables) { variable in
                        VariableRow(store: store, variable: variable, canvas: canvas)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)
        }
    }

    private var footer: some View {
        HStack(spacing: Token.Space.md) {
            TextField("new variable", text: $draftName)
                .textFieldStyle(.roundedBorder)
                .font(Token.Text.value)
                .onSubmit { create(.colour(store.style.fill ?? store.style.stroke)) }
            Menu {
                Button("Colour") { create(.colour(store.style.fill ?? store.style.stroke)) }
                Button("Number") { create(.number(store.style.cornerRadius)) }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Token.accent)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 22)
            .help("Create a variable")
        }
        .padding(.horizontal, Token.Size.separatorInset)
        .padding(.top, Token.Space.md)
        .padding(.bottom, Token.Space.xl)
    }

    private func create(_ value: VariableValue) {
        let name = draftName.isEmpty ? store.suggestedName(for: .fill) : draftName
        if store.createVariable(named: name, value: value) != nil { draftName = "" }
    }
}

/// One variable: its value in the mode on screen, its name, and a way to remove
/// it. The name is a live field rather than click-to-edit — renaming a token is
/// common enough that hiding it behind a gesture is worse than the extra chrome.
private struct VariableRow: View {
    @ObservedObject var store: SketchStore
    let variable: Variable
    let canvas: () -> CanvasView?

    @State private var draft = ""
    @State private var loaded = false

    var body: some View {
        HStack(spacing: Token.Space.md) {
            editor
            HStack(spacing: 0) {
                Text("$")
                    .font(Token.Text.label)
                    .foregroundStyle(Token.accent.opacity(0.55))
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(Token.Text.label)
                    .foregroundStyle(Token.accent)
                    .onSubmit {
                        // A rejected rename — empty, or a name already taken —
                        // puts the field back rather than leaving a lie in it.
                        if !store.renameVariable(variable.id, to: draft) { draft = variable.name }
                    }
            }
            Spacer(minLength: Token.Space.sm)
            MiniButton(symbol: "trash", help: "Delete \(variable.token)") {
                store.deleteVariable(variable.id, canvas: canvas())
            }
        }
        .padding(.horizontal, Token.Size.separatorInset)
        .frame(height: Token.Size.row + 2)
        .onAppear { if !loaded { draft = variable.name; loaded = true } }
        .onChange(of: variable.name) { _, name in draft = name }
    }

    @ViewBuilder
    private var editor: some View {
        let value = store.value(of: variable.id, in: store.mode)
        if variable.isColour {
            ColorControl(current: value?.colourHex,
                         presets: Palette.fillPresets,
                         recents: store.recentColors,
                         allowsNone: false,
                         inlineCount: 0) { hex in
                guard let hex else { return }
                store.setVariableValue(.colour(hex), for: variable.id, mode: store.mode)
                store.noteRecent(hex)
            }
        } else {
            NumberControl(value: value?.doubleValue ?? 0,
                          range: 0...200,
                          step: 1,
                          presets: [0, 2, 4, 8, 12, 16, 24]) { number in
                store.setVariableValue(.number(number), for: variable.id, mode: store.mode)
            }
        }
    }
}
