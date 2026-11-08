internal import TerminalKitStyle

/// SGR as a tool's output uses it (note n30): the foreground in its 16, 256 and true colours, in the semicolon and colon forms; bold, dim,
/// italic, underline with its kinds, and strikethrough, each switched off on its own; 0 or nothing resets. A background, inverse,
/// blinking and fonts are read and not drawn.
extension OutputEscapes {
    /// `style` after the SGR whose parameters are `parameters`; nil for a private sequence (`ESC [ ? … m`), which is not SGR.
    static func styled(_ style: Style, sgr parameters: ArraySlice<UInt8>) -> Style? {
        guard parameters.allSatisfy({ (0x30 ... 0x3B).contains($0) }) else { return nil }
        // Groups split by ';', each a number and its ':' sub-parameters; an empty number is 0.
        let groups = parameters.split(separator: 0x3B, omittingEmptySubsequences: false)
            .map { group in
                group.split(separator: 0x3A, omittingEmptySubsequences: false).map(number)
            }
        var style = style
        var index = 0
        while index < groups.count {
            let group = groups[index]
            let code = group.first.flatMap { $0 } ?? 0
            index += 1
            switch code {
                case 0:
                    let link = style.link
                    style = Style()
                    style.link = link
                case 1: style.bold = true
                case 2: style.dim = true
                case 3: style.italic = true
                case 4: style.underline = underline(group.count > 1 ? group[1] ?? 1 : 1)
                case 9: style.strikethrough = true
                case 21: style.underline = .double
                case 22:
                    style.bold = false
                    style.dim = false
                case 23: style.italic = false
                case 24: style.underline = .none
                case 29: style.strikethrough = false
                case 30 ... 37: style.fg = .indexed(UInt8(code - 30))
                case 39: style.fg = .default
                case 90 ... 97: style.fg = .indexed(UInt8(code - 90 + 8))
                case 38, 48, 58:
                    let color: Color?
                    if group.count > 1 {
                        color = extended(Array(group.dropFirst()))
                    } else {
                        // The semicolon form takes the groups after it: 5;n or 2;r;g;b.
                        let mode = index < groups.count ? groups[index].first.flatMap { $0 } : nil
                        let taken = mode == 5 ? 2 : mode == 2 ? 4 : 0
                        let end = Swift.min(groups.count, index + taken)
                        color = extended(groups[index ..< end].map { $0.first.flatMap { $0 } })
                        index = end
                    }
                    if code == 38, let color { style.fg = color }
                default: break
            }
        }
        return style
    }

    private static func number(_ digits: ArraySlice<UInt8>) -> Int? {
        guard !digits.isEmpty, digits.count <= 6 else { return digits.isEmpty ? nil : Int.max }
        return digits.reduce(0) { $0 * 10 + Int($1 - 0x30) }
    }

    private static func underline(_ kind: Int) -> UnderlineStyle {
        switch kind {
            case 0: .none
            case 2: .double
            case 3: .curly
            case 4: .dotted
            case 5: .dashed
            default: .single
        }
    }

    /// A colour from `5, n` or `2, r, g, b`; the colon form may put a colour space before r (`2::r:g:b`), which is skipped.
    private static func extended(_ values: [Int?]) -> Color? {
        guard let mode = values.first.flatMap({ $0 }) else { return nil }
        let rest = Array(values.dropFirst())
        switch mode {
            case 5:
                guard let index = rest.first.flatMap({ $0 }), (0 ... 255).contains(index) else { return nil }
                return .indexed(UInt8(index))
            case 2:
                let channels = rest.count >= 4 ? Array(rest.suffix(3)) : rest
                guard channels.count == 3 else { return nil }
                let bytes = channels.compactMap { $0.flatMap { (0 ... 255).contains($0) ? UInt8($0) : nil } }
                guard bytes.count == 3 else { return nil }
                return .rgb(r: bytes[0], g: bytes[1], b: bytes[2])
            default: return nil
        }
    }
}
