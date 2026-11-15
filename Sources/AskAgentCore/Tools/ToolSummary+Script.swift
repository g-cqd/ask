internal import Foundation

extension ToolSummary {
    /// A `codemode` script in a line (ADR-0156): how long it is, and the tools it names, in the order it first names them. The
    /// names are read off the text (`tools.name`, `tools["name"]`): what a person is shown before they allow it, not a promise
    /// of what it calls.
    static func script(_ code: String) -> String {
        let lines = code.split(whereSeparator: \.isNewline).count { !$0.allSatisfy(\.isWhitespace) }
        var named: [String] = []
        var rest = code[...]
        while let found = rest.range(of: "tools") {
            rest = rest[found.upperBound...]
            let name: Substring
            if rest.hasPrefix(".") {
                name = rest.dropFirst().prefix { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }
            } else if rest.hasPrefix("[\"") || rest.hasPrefix("['") {
                name = rest.dropFirst(2).prefix { $0 != "\"" && $0 != "'" && !$0.isNewline }
            } else {
                continue
            }
            if !name.isEmpty, !named.contains(String(name)) { named.append(String(name)) }
        }
        let length = "script of \(lines) line\(lines == 1 ? "" : "s")"
        return named.isEmpty ? length : length + " calling " + named.joined(separator: ", ")
    }
}
