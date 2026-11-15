/// A tool a script may call: its name as the model knows it, the name a script writes after `tools.`, and what it is for.
package struct CodemodeTool: Sendable, Equatable, Codable {
    /// The tool's own name, such as `mcp__dev-radius__search`.
    package let name: String
    package let description: String

    package init(name: String, description: String) {
        self.name = name
        self.description = description
    }

    /// The name as a JavaScript identifier: what is not a letter, a digit, `_` or `$` becomes `_`, and a leading digit gets one
    /// before it, so `my-tool` is `tools.my_tool` as well as `tools["my-tool"]` (pi's rule).
    package var identifier: String {
        var identifier = String(
            name.map { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "$") ? $0 : "_" }
        )
        if identifier.first?.isNumber == true { identifier = "_" + identifier }
        return identifier.isEmpty ? "_" : identifier
    }
}
