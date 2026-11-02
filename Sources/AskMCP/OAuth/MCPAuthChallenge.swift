public import Foundation

/// What a server's `401` or `403` asks for, from its `WWW-Authenticate: Bearer …` header (RFC 6750 §3, RFC 9728 §5.1): where its
/// protected resource metadata is, the scope it wants, and why it refused.
public struct MCPAuthChallenge: Sendable, Equatable {
    /// The protected resource metadata's address (`resource_metadata`).
    public var resourceMetadata: URL?
    /// The scopes the server wants, space-separated (`scope`).
    public var scope: String?
    /// Why it refused (`error`): `invalid_token`, `insufficient_scope`.
    public var error: String?

    /// A challenge with these parts.
    public init(resourceMetadata: URL? = nil, scope: String? = nil, error: String? = nil) {
        self.resourceMetadata = resourceMetadata
        self.scope = scope
        self.error = error
    }

    /// The Bearer challenge in `header`, or nil when it has none.
    public init?(header: String) {
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("bearer"), trimmed.count == 6 || trimmed.dropFirst(6).first == " " else {
            return nil
        }
        let parameters = Self.parameters(String(trimmed.dropFirst(6)))
        self.init(
            resourceMetadata: parameters["resource_metadata"].flatMap(URL.init(string:)),
            scope: parameters["scope"],
            error: parameters["error"]
        )
    }

    /// `name=value` and `name="quoted value"` pairs separated by commas; a comma inside quotes is the value's.
    private static func parameters(_ text: String) -> [String: String] {
        var found: [String: String] = [:]
        var rest = Substring(text)
        while true {
            rest = rest.drop { $0 == " " || $0 == "," }
            guard let equals = rest.firstIndex(of: "=") else { return found }
            let name = rest[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            rest = rest[rest.index(after: equals)...].drop { $0 == " " }
            var value = ""
            if rest.first == "\"" {
                rest = rest.dropFirst()
                while let character = rest.first, character != "\"" {
                    if character == "\\", let escaped = rest.dropFirst().first {
                        value.append(escaped)
                        rest = rest.dropFirst(2)
                    } else {
                        value.append(character)
                        rest = rest.dropFirst()
                    }
                }
                rest = rest.dropFirst()
            } else {
                let end = rest.firstIndex(of: ",") ?? rest.endIndex
                value = rest[..<end].trimmingCharacters(in: .whitespaces)
                rest = rest[end...]
            }
            if !name.isEmpty { found[name] = value }
        }
    }
}
