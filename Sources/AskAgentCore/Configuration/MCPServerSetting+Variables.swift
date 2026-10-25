internal import Foundation

extension MCPServerSetting {
    /// Variables this server's environment and headers name as `${NAME}`. These are the places the host expands them.
    /// Commands must not inherit these variables by default (ADR-0106).
    public var referencedVariables: Set<String> {
        var names = Set<String>()
        for value in Array(env.values) + Array(headers.values) {
            _ = Self.expandingVariables(in: value) { name in
                if !name.isEmpty { names.insert(name) }
                return ""
            }
        }
        return names
    }

    /// Replaces each closed `${NAME}` reference using the same walk that discovers credential names.
    /// - Parameters:
    ///   - text: A server environment or header value.
    ///   - value: Supplies the replacement for each reference, including an empty name.
    /// - Returns: The expanded text; an unterminated reference remains literal.
    /// - Throws: The error from `value` when a reference cannot be resolved.
    public static func expandingVariables<E: Error>(
        in text: String, value: (String) throws(E) -> String
    ) throws(E) -> String {
        var result = ""
        var rest = Substring(text)
        while let start = rest.range(of: "${") {
            guard let end = rest[start.upperBound...].firstIndex(of: "}") else { break }
            result += rest[..<start.lowerBound] + (try value(String(rest[start.upperBound ..< end])))
            rest = rest[rest.index(after: end)...]
        }
        return result + rest
    }
}
