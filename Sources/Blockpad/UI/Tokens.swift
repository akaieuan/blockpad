import SwiftUI

/// One scale for the whole app.
///
/// The chrome drifted while it was being built — hairlines running into rounded
/// corners, ring-style swatches beside solid-filled squares, four different
/// corner radii, label opacities picked per view. Every one of those is cheap to
/// fix and impossible to keep fixed without a shared vocabulary, so this is it.
/// Nothing in `UI/` should hard-code a number that belongs here.
enum Token {

    /// 4pt base, the same reason Tailwind and Apple both land on one.
    enum Space {
        static let xs: CGFloat = 2
        static let sm: CGFloat = 4
        static let md: CGFloat = 6
        static let lg: CGFloat = 8
        static let xl: CGFloat = 12
        static let xxl: CGFloat = 16
    }

    /// Radii nest: a control inside a container is always the smaller step, so
    /// the curves stay concentric rather than fighting.
    enum Radius {
        static let micro: CGFloat = 5
        static let control: CGFloat = 7
        static let group: CGFloat = 9
        static let panel: CGFloat = 14
        static let dock: CGFloat = 16
    }

    enum Size {
        static let row: CGFloat = 30
        static let control: CGFloat = 20
        static let swatch: CGFloat = 13
        static let glyph: CGFloat = 13
        /// Separators stop short of the panel edge; a hairline that runs into a
        /// rounded corner is the single most obvious "unfinished" tell.
        static let separatorInset: CGFloat = 11
    }

    enum Text {
        static let header = Font.system(size: 11, weight: .semibold)
        static let label = Font.system(size: 11, weight: .medium)
        static let value = Font.system(size: 10.5, weight: .medium)
        static let micro = Font.system(size: 9.5, weight: .semibold)
    }

    /// Opacity ladder. Dark surfaces need more signal than light ones for the
    /// same perceived weight, so these lean brighter than a light-only design
    /// would pick.
    enum Ink {
        static let strong = 0.92
        static let primary = 0.78
        static let secondary = 0.58
        static let tertiary = 0.42
        static let hairline = 0.09
        static let hover = 0.08
        static let sunken = 0.05
    }

    static var accent: Color { Color(nsColor: Palette.selection) }
    static var accentSoft: Color { Color(nsColor: Palette.selection).opacity(0.16) }
}

extension View {
    /// Hairline that respects the container's inner padding on both sides.
    func rowSeparator(leadingInset: CGFloat) -> some View {
        overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(Token.Ink.hairline))
                .frame(height: 1)
                .padding(.leading, leadingInset)
                .padding(.trailing, Token.Size.separatorInset)
        }
    }
}
