import SwiftUI

/// Component drawer. Click drops the preset into the middle of the viewport
/// already selected, so it can be dragged immediately.
///
/// Categorised because the set outgrew a single grid — thirty-odd tiles in one
/// scroll is a worse experience than eight were, not a better one.
struct LibraryPanel: View {
    @ObservedObject var store: SketchStore
    var maxHeight: CGFloat = .infinity
    var canvas: () -> CanvasView?

    @State private var category: ComponentCategory = .layout

    private let columns = [GridItem(.adaptive(minimum: 76), spacing: Token.Space.md)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            categoryPicker
            ScrollView(.vertical) {
                LazyVGrid(columns: columns, spacing: Token.Space.md) {
                    ForEach(ComponentPreset.inCategory(category)) { preset in
                        LibraryTile(preset: preset) { canvas()?.insert(preset) }
                    }
                }
                .padding(.horizontal, Token.Size.separatorInset)
                .padding(.vertical, Token.Space.xl)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)
        }
        .frame(width: 268)
        .frame(maxHeight: maxHeight)
        .fixedSize(horizontal: false, vertical: true)
        .glassSurface()
    }

    private var header: some View {
        HStack(spacing: Token.Space.md) {
            Text("Components")
                .font(Token.Text.header)
                .foregroundStyle(.primary.opacity(Token.Ink.strong))
            Spacer()
            Text("\(ComponentPreset.inCategory(category).count)")
                .font(Token.Text.micro)
                .monospacedDigit()
                .foregroundStyle(.primary.opacity(Token.Ink.tertiary))
            MiniButton(symbol: "xmark", help: "Close   Esc") {
                store.libraryOpen = false
            }
        }
        .padding(.horizontal, Token.Size.separatorInset)
        .padding(.top, Token.Space.lg + 2)
        .padding(.bottom, Token.Space.lg)
    }

    private var categoryPicker: some View {
        HStack(spacing: 1) {
            ForEach(ComponentCategory.allCases) { option in
                Button { category = option } label: {
                    Text(option.rawValue)
                        .font(Token.Text.value)
                        .foregroundStyle(category == option
                                         ? Token.accent
                                         : .primary.opacity(Token.Ink.secondary))
                        .frame(maxWidth: .infinity)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: Token.Radius.micro, style: .continuous)
                                .fill(category == option ? Token.accentSoft : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
        .padding(.horizontal, Token.Size.separatorInset)
        .animation(.easeOut(duration: 0.14), value: category)
    }
}

private struct LibraryTile: View {
    let preset: ComponentPreset
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: Token.Space.md) {
                Image(systemName: preset.symbol)
                    .font(.system(size: 15, weight: .light))
                    .foregroundStyle(.primary.opacity(hovering ? Token.Ink.strong : Token.Ink.primary))
                    .frame(height: 19)
                Text(preset.name)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.primary.opacity(Token.Ink.secondary))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Token.Space.lg + 1)
            .background(
                RoundedRectangle(cornerRadius: Token.Radius.group, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? Token.Ink.hover + 0.02 : Token.Ink.sunken))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Token.Radius.group, style: .continuous)
                    .strokeBorder(Color.primary.opacity(hovering ? Token.Ink.hairline + 0.04 : 0),
                                  lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Token.Radius.group, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Insert \(preset.name)")
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}
