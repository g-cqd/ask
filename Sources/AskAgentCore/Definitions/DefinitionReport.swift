/// How one definition file (a skill, or any harness's agent definition) was read: what `ask skills --inspect` prints.
public struct DefinitionReport: Sendable {
    public let path: String
    public let file: DefinitionFile

    public init(path: String, text: String) {
        self.path = path
        file = DefinitionFile(parsing: text, isTOML: path.lowercased().hasSuffix(".toml"))
    }

    public var lines: [String] {
        var lines = [
            "\(path): \(format), \(file.entries.count) fields, \(file.hints.count) comment hints, body \(file.body.count) characters"
        ]
        lines.append("    fields: " + file.entries.map(\.key).joined(separator: ", "))
        let tools = ToolReference.parse(file.value("allowed-tools")) + ToolReference.parse(file.value("tools"))
        if !tools.isEmpty {
            lines.append(
                "    tools: "
                    + tools.map { reference in
                        reference.ask.map { "\(reference.token)→\($0)" } ?? "\(reference.token)→?"
                    }
                    .joined(separator: ", "))
        }
        let models = ModelPreference(file)
        if !models.tokens.isEmpty || models.inheritsParent {
            lines.append(
                "    models: \(models.tokens.joined(separator: " > "))\(models.inheritsParent ? " (then the parent's)" : "")"
            )
        }
        for note in file.diagnostics { lines.append("    note: \(note)") }
        return lines
    }

    private var format: String {
        switch file.format {
            case .yaml: "yaml head"
            case .toml: "toml"
            case .none: "no head"
        }
    }
}
