internal import Foundation

/// What two providers' pasted-code parsers share: telling a URL from a bare token, and picking the one code and at most one state
/// out of a callback's parameters. Each provider still decides which host, path and token shapes it accepts.
enum PastedAuthorization {
    /// Whether `text` begins with a URL scheme (`https:`, `javascript:`), as opposed to being a bare code.
    static func hasScheme(_ text: String) -> Bool {
        guard let colon = text.firstIndex(of: ":"), let first = text.first, first.isASCII, first.isLetter else {
            return false
        }
        return text[text.index(after: text.startIndex) ..< colon]
            .allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "+" || $0 == "." || $0 == "-") }
    }

    /// The code and state in `items`, when there is exactly one code, at most one state and no `error`.
    static func codeAndState(in items: [URLQueryItem]) -> (code: String, state: String?)? {
        func values(_ name: String) -> [String] { items.filter { $0.name == name }.map { $0.value ?? "" } }
        let codes = values("code")
        let states = values("state")
        guard codes.count == 1, states.count <= 1, values("error").isEmpty else { return nil }
        return (codes[0], states.first)
    }
}
