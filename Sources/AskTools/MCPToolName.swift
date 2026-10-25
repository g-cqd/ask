/// The name ask gives a server's tool: `mcp__<server>__<tool>` (ADR-0099; ADR-0092 keeps such names whole).
///
/// Providers accept 64 characters of letters, digits, `-` and `_`. A tool name outside that is sanitised, and a sanitised or cut name
/// gets a short hash of the original, so two tools that sanitise alike are still two names, and the same tool has the same name
/// every time: a resumed session calls what it called before.
enum MCPToolName {
    static let prefix = "mcp__"
    static let maximumLength = 64

    /// The name for `tool` of `server`.
    static func make(server: String, tool: String) -> String {
        let head = prefix + server + "__"
        let clean = String(String.UnicodeScalarView(tool.unicodeScalars.map { isAcceptable($0) ? $0 : "_" }))
        if clean == tool, head.utf8.count + tool.utf8.count <= maximumLength { return head + tool }
        let hash = hex(of: tool)
        let room = max(0, maximumLength - head.utf8.count - hash.utf8.count - 1)
        return head + String(clean.prefix(room)) + "_" + hash
    }

    /// Whether `name` is one a provider takes: 1 to 64 of letters, digits, `-` and `_`.
    static func isAcceptable(_ name: String) -> Bool {
        (1 ... maximumLength).contains(name.utf8.count) && name.unicodeScalars.allSatisfy(isAcceptable)
    }

    /// Whether `name` is a server's tool.
    static func isMCP(_ name: String) -> Bool { name.hasPrefix(prefix) }

    private static func isAcceptable(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
            case 0x30 ... 0x39, 0x41 ... 0x5A, 0x61 ... 0x7A, 0x2D, 0x5F: true
            default: false
        }
    }

    /// Eight hex digits of FNV-1a over the name's bytes: stable across runs and builds, which Swift's `hashValue` is not.
    private static func hex(of text: String) -> String {
        var hash: UInt32 = 0x811C_9DC5
        for byte in text.utf8 { hash = (hash ^ UInt32(byte)) &* 0x0100_0193 }
        let digits = String(hash, radix: 16)
        return String(repeating: "0", count: 8 - digits.count) + digits
    }
}
