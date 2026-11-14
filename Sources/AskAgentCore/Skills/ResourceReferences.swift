/// `@server:uri` in a message (roadmap 0067): a server's resource, read when the message is sent and attached after what was typed, as a
/// task is (0186); each once, in the order named. Only a word that starts with `@` and names a server that has resources counts, and only
/// the typed line is read for them; anything else, a file's `@path` among it, stays text.
public enum ResourceReferences {
    public static let marker = "\n\n--- resource "
    /// The most of one resource attached, in characters; the model can read the rest itself.
    public static let limit = 64 * 1024

    /// The references in the typed part of `text` to `servers`, each once, in order.
    public static func words(_ text: String, servers: Set<String>) -> [ResourceReference] {
        var found: [ResourceReference] = []
        var seen: Set<ResourceReference> = []
        for word in SkillInvocation.shown(text).split(whereSeparator: \.isWhitespace) where word.first == "@" {
            guard let colon = word.firstIndex(of: ":") else { continue }
            let server = String(word[word.index(after: word.startIndex) ..< colon])
            // A sentence's punctuation after the URI is the sentence's.
            var uri = word[word.index(after: colon)...]
            while let last = uri.last, ".,;!?".contains(last) { uri = uri.dropLast() }
            let reference = ResourceReference(server: server, uri: String(uri))
            if servers.contains(server), !uri.isEmpty, seen.insert(reference).inserted { found.append(reference) }
        }
        return found
    }

    /// `text` with each read attached after it: what was read of a reference, or why it could not be.
    public static func attach(_ text: String, _ read: [(ResourceReference, String)]) -> String {
        text
            + read.map { reference, body in
                let cut =
                    body.count > limit
                    ? body.prefix(limit) + "\n[cut at \(limit / 1024) KB; read the rest with server_resource]"
                    : body[...]
                // A server's text is not the person's (ADR-0150): said so, and unable to close its section.
                return "\(marker)\(reference.server):\(reference.uri) ---\n"
                    + UntrustedText.notice(from: "the MCP server \(reference.server)") + "\n"
                    + UntrustedText.insideAttachment(String(cut)) + "\n--- end of resource ---"
            }
            .joined()
    }
}
