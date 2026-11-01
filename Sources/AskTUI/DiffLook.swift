internal import TerminalKitStyle

/// How an edit's diff rows are drawn (roadmap 0152, phase 3): a removed row on the theme's red tint and an added row on its green one,
/// whole, and each marker in red or green, which is all that sets the rows apart with tinting off.
struct DiffLook: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case kept, removed, added
        /// A unified diff's file header (`diff`, `index`, `---`, `+++`), drawn bold.
        case header
        /// A unified diff's hunk header (`@@ -1,3 +1,4 @@`), drawn in cyan.
        case hunk
    }

    /// How the lines are marked: an edit's `- ` and `+ ` (two columns), or a unified diff's `-` and `+` (one), with its headers.
    enum Format: Sendable, Equatable {
        case edit, unified
    }

    private var removed: Color
    private var added: Color
    var format: Format

    init(theme: ScreenTheme, format: Format = .edit) {
        removed = theme.tinted ? theme.diffRemoved : .default
        added = theme.tinted ? theme.diffAdded : .default
        self.format = format
    }

    /// What hard line `line` of an edit's diff is, by its marker: `- `, `+ `, or anything else, kept.
    static func kind(of line: Substring) -> Kind {
        if line.hasPrefix("- ") { return .removed }
        if line.hasPrefix("+ ") { return .added }
        return .kept
    }

    /// The kind of each hard line of `text`. In a unified diff, a line before a file's first hunk is a header, whatever it starts with.
    static func kinds(of text: String, format: Format = .edit) -> [Kind] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard format == .unified else { return lines.map(kind(of:)) }
        var inHunk = false
        return lines.map { line in
            if line.hasPrefix("@@") {
                inHunk = true
                return .hunk
            }
            if line.hasPrefix("diff ") { inHunk = false }
            guard inHunk else { return .header }
            if line.hasPrefix("+") { return .added }
            if line.hasPrefix("-") { return .removed }
            return .kept
        }
    }

    /// The bytes of a line's marker, in `format`, by its kind: none for a header or a kept line.
    static func markerWidth(_ kind: Kind, format: Format) -> Int {
        guard kind == .removed || kind == .added else { return 0 }
        return format == .edit ? 2 : 1
    }

    /// `base` with the tint of a row of `kind`: a kept row keeps the block's.
    func style(_ kind: Kind, over base: Style) -> Style {
        var style = base
        switch kind {
            case .kept: break
            case .removed: style.bg = removed
            case .added: style.bg = added
            case .header: style.bold = true
            case .hunk: style.fg = .indexed(6)
        }
        return style
    }

    /// The marker of the first row of a removed or added line, at column `inset`, in red or green over the row's style.
    func marker(_ kind: Kind, inset: Int, over base: Style) -> ScreenComposer.Accent? {
        var style = base
        switch kind {
            case .kept, .header, .hunk: return nil
            case .removed: style.fg = .indexed(1)
            case .added: style.fg = .indexed(2)
        }
        return ScreenComposer.Accent(columns: inset ..< inset + 1, style: style)
    }
}
