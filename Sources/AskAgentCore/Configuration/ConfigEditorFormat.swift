/// The layout a saved file keeps: whether it is pretty, its indent unit, its key separator, and its final newline.
struct ConfigEditorFormat: Sendable, Equatable {
    var pretty = false
    var indent = "  "
    var foundationSeparator = false
    var trailingNewline = true

    /// The layout of `text`: pretty when it spans lines, with the first indented line's prefix as the unit.
    init(of text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else {
            trailingNewline = text.hasSuffix("\n")
            return
        }
        pretty = true
        indent =
            lines.dropFirst().lazy
            .compactMap { line -> String? in
                let prefix = line.prefix { $0 == " " || $0 == "\t" }
                return prefix.isEmpty ? nil : String(prefix)
            }
            .first ?? "  "
        foundationSeparator = text.contains("\" : \"")
        trailingNewline = text.hasSuffix("\n")
    }
}
