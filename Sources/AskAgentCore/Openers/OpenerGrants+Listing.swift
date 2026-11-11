/// What `/config openers` shows and takes back (ADR-0148).
extension OpenerGrants {
    /// What revoking did.
    public enum Revocation: Sendable, Equatable {
        /// These commands, as shown, are no longer allowed always.
        case revoked([String])
        /// Nothing was revoked: why.
        case nothing(String)
    }

    /// The commands allowed always, numbered as ``revoke(naming:)`` takes them, for a person to read.
    public var report: [String] {
        let listed = listing
        guard !listed.isEmpty else {
            return ["No opener command is allowed always. Answer a command's question with \"always\" to allow one."]
        }
        return ["Opener commands allowed always (/config openers revoke N, or revoke all):"]
            + listed.enumerated()
            .map { index, entry in
                "  \(index + 1). \(OpenerRun.shown(entry.grant.command))  for \(entry.grant.match)"
            }
    }

    /// Takes back what `word` names: a number from ``report``, or `all`.
    public mutating func revoke(naming word: String) -> Revocation {
        let listed = listing
        if word.lowercased() == "all" {
            guard !listed.isEmpty else { return .nothing("Nothing is allowed always.") }
            for entry in listed { revoke(entry.key) }
            return .revoked(listed.map { OpenerRun.shown($0.grant.command) })
        }
        guard let number = Int(word) else { return .nothing("Say which: a number from the list, or all.") }
        guard listed.indices.contains(number - 1) else {
            return .nothing("There is no \(number): the list has \(listed.count).")
        }
        revoke(listed[number - 1].key)
        return .revoked([OpenerRun.shown(listed[number - 1].grant.command)])
    }
}
