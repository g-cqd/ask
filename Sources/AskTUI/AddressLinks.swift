internal import TerminalKitText

/// Web and email addresses found in a row of text (roadmap 0075), beside ``PathLinks``' paths: `http://`, `https://` and `mailto:`
/// addresses, and bare email addresses, which become `mailto:` links. Nothing that is not printable ASCII becomes a link, so every URI
/// can be sent to the terminal as it is.
enum AddressLinks {
    /// The schemes an address may start with.
    private static let schemes = ["https://", "http://", "mailto:"]
    /// What ends an address outright.
    // @dl:accept -- a set of characters is data, like any other list of literals
    private static let stops: Set<Character> = [" ", "\t", "\"", "'", "<", ">", "`", "[", "]", "{", "}", "|", "\\", "^"]
    /// What an address does not end with: sentence punctuation after it.
    private static let trailing: Set<Character> = [".", ",", ":", ";", "!", "?"]

    /// The addresses in one row, left to right.
    static func links(in text: String) -> [PathLinks.Link] {
        let characters = Array(text)
        var columns = [0]
        for character in characters { columns.append(columns.last! + UnicodeWidth.displayWidth(of: String(character))) }
        var found: [(Range<Int>, String)] = []
        var index = 0
        while index < characters.count {
            if let (end, uri) = web(characters, at: index) {
                found.append((index ..< end, uri))
                index = end
            } else if characters[index] == "@", let (range, uri) = email(characters, at: index),
                !found.contains(where: { $0.0.overlaps(range) })
            {
                found.append((range, uri))
                index = range.upperBound
            } else {
                index += 1
            }
        }
        return found.map { range, uri in
            PathLinks.Link(columns: columns[range.lowerBound] ..< columns[range.upperBound], uri: uri)
        }
    }

    /// A web or `mailto:` address starting at `start`: where it ends and its URI.
    private static func web(_ characters: [Character], at start: Int) -> (Int, String)? {
        guard start == 0 || !isWordCharacter(characters[start - 1]) else { return nil }
        guard
            let scheme = schemes.first(where: { scheme in
                start + scheme.count <= characters.count && String(characters[start ..< start + scheme.count]) == scheme
            })
        else { return nil }
        var end = start + scheme.count
        var depth = 0
        while end < characters.count, !stops.contains(characters[end]), !characters[end].isWhitespace {
            if characters[end] == "(" { depth += 1 }
            if characters[end] == ")" {
                guard depth > 0 else { break }
                depth -= 1
            }
            end += 1
        }
        while end > start + scheme.count, trailing.contains(characters[end - 1]) { end -= 1 }
        let rest = characters[(start + scheme.count) ..< end]
        guard rest.contains(where: { $0.isLetter || $0.isNumber }) else { return nil }
        let uri = String(characters[start ..< end])
        guard isPrintableASCII(uri) else { return nil }
        if scheme == "mailto:", !isEmail(Array(rest)) { return nil }
        return (end, uri)
    }

    /// A bare email address around the `@` at `at`, as a range of characters and a `mailto:` URI.
    private static func email(_ characters: [Character], at sign: Int) -> (Range<Int>, String)? {
        var start = sign
        while start > 0, isLocalCharacter(characters[start - 1]) { start -= 1 }
        var end = sign + 1
        while end < characters.count, isDomainCharacter(characters[end]) { end += 1 }
        while end > sign + 1, characters[end - 1] == "." { end -= 1 }
        // Not part of something bigger: `git@github.com:org/repo` is a remote, `a/b@c.d` a path.
        if start > 0, ["/", ":", "@"].contains(characters[start - 1]) { return nil }
        if end < characters.count, [":", "/", "@"].contains(characters[end]) { return nil }
        let address = Array(characters[start ..< end])
        guard isEmail(address) else { return nil }
        let uri = "mailto:" + String(address)
        return isPrintableASCII(uri) ? (start ..< end, uri) : nil
    }

    /// Whether `address` is `local@domain.tld`: a local part not starting with a dot, a domain with a dot, a top level of 2+ letters.
    private static func isEmail(_ address: [Character]) -> Bool {
        guard let at = address.firstIndex(of: "@"), at > 0, address[0] != ".",
            address.filter({ $0 == "@" }).count == 1
        else { return false }
        let domain = address[(at + 1)...]
        guard let dot = domain.lastIndex(of: "."), dot > domain.startIndex else { return false }
        let top = domain[(dot + 1)...]
        return top.count >= 2 && top.allSatisfy { $0.isASCII && $0.isLetter }
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "/"
    }

    private static func isLocalCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || "._%+-".contains(character))
    }

    private static func isDomainCharacter(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber || character == "." || character == "-")
    }

    private static func isPrintableASCII(_ text: String) -> Bool { text.utf8.allSatisfy { $0 > 0x20 && $0 < 0x7F } }
}
