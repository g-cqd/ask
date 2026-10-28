internal import Foundation

/// The home folder written `~` (roadmap 0128), for what ask says about paths. Never for a command as it was run, a file's content or a
/// tool's output: those are verbatim to what happened.
public enum HomePath {
    /// `text` with each path that starts at `home` written from `~`. A path starts there only at a boundary: after the start, a space, a
    /// quote, a bracket, `=` or `:`, and not before more name (`/Users/gigi2` is not under `/Users/gigi`).
    public static func abbreviate(_ text: String, home: String?) -> String {
        guard var home, !home.isEmpty else { return text }
        while home.count > 1, home.hasSuffix("/") { home.removeLast() }
        guard home != "/", text.contains(home) else { return text }
        // @dl:accept -- two character sets, what may precede and follow a path; they read alike because both are punctuation
        let before: Set<Character> = [" ", "\t", "\n", "\"", "'", "`", "(", "[", "{", "<", "=", ":", ","]
        let after: Set<Character> = ["/", " ", "\t", "\n", "\"", "'", "`", ")", "]", "}", ">", ":", ",", ";", "."]
        var result = ""
        var rest = Substring(text)
        var previous: Character?
        while let found = rest.range(of: home) {
            let head = rest[rest.startIndex ..< found.lowerBound]
            let last = head.last ?? previous
            let next = rest[found.upperBound...].first
            let startsPath = last.map(before.contains) ?? true
            let endsPath = next.map(after.contains) ?? true
            result += head
            result += startsPath && endsPath ? "~" : home
            previous = startsPath && endsPath ? "~" : home.last
            rest = rest[found.upperBound...]
        }
        return result + rest
    }
}
