/// One line of a head with its indentation worked out.
struct YAMLLine {
    let indent: Int
    /// The line without its indentation.
    let text: String

    init(_ raw: String) {
        indent = raw.indentation
        text = raw.trimmingWhitespace()
    }

    var isBlank: Bool { text.isEmpty }
    var isComment: Bool { text.first == "#" }
    var isItem: Bool { text == "-" || text.hasPrefix("- ") }
}
