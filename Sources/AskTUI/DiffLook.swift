internal import TerminalKitStyle

/// How an edit's diff rows are drawn (roadmap 0152, phase 3): a removed row on the theme's red tint and an added row on its green one,
/// whole, and each marker in red or green, which is all that sets the rows apart with tinting off.
struct DiffLook: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case kept, removed, added
    }

    private var removed: Color
    private var added: Color

    init(theme: ScreenTheme) {
        removed = theme.tinted ? theme.diffRemoved : .default
        added = theme.tinted ? theme.diffAdded : .default
    }

    /// What hard line `line` of an edit's diff is, by its marker: `- `, `+ `, or anything else, kept.
    static func kind(of line: Substring) -> Kind {
        if line.hasPrefix("- ") { return .removed }
        if line.hasPrefix("+ ") { return .added }
        return .kept
    }

    /// The bytes of `line`'s marker, which are no part of its code: two for `- ` and `+ `. A kept line's two spaces are lexed with it,
    /// as leading space, which no lexer here reads differently.
    static func markerWidth(of line: Substring) -> Int {
        kind(of: line) == .kept ? 0 : 2
    }

    /// The kind of each hard line of `text`.
    static func kinds(of text: String) -> [Kind] {
        text.split(separator: "\n", omittingEmptySubsequences: false).map(kind(of:))
    }

    /// `base` with the tint of a row of `kind`: a kept row keeps the block's.
    func style(_ kind: Kind, over base: Style) -> Style {
        var style = base
        switch kind {
            case .kept: break
            case .removed: style.bg = removed
            case .added: style.bg = added
        }
        return style
    }

    /// The marker of the first row of a removed or added line, at column `inset`, in red or green over the row's style.
    func marker(_ kind: Kind, inset: Int, over base: Style) -> ScreenComposer.Accent? {
        var style = base
        switch kind {
            case .kept: return nil
            case .removed: style.fg = .indexed(1)
            case .added: style.fg = .indexed(2)
        }
        return ScreenComposer.Accent(columns: inset ..< inset + 1, style: style)
    }
}
