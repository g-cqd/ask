internal import AemiJSON
internal import AskAI
internal import CryptoKit
internal import Foundation

/// The commands the person allowed always (roadmap 0216, ADR-0148): kept in ask's state, each under a hash of the command's arguments
/// as written and what its rule matches, so editing either asks again.
public struct OpenerGrants: Sendable, Equatable {
    /// One command allowed always, as it was when it was allowed.
    public struct Grant: Codable, Sendable, Equatable {
        public var command: [String]
        /// What the rule matched, in words.
        public var match: String
    }

    private var entries: [String: Grant] = [:]

    public init() {}

    /// Where the store is kept: `openers.json` in ask's state directory.
    public static func path(environment: [String: String], home: String? = nil) -> String {
        SessionDirectory.stateRoot(environment: environment, home: home ?? NSHomeDirectory()) + "/openers.json"
    }

    /// The key `rule` is allowed under: the SHA-256 of its command's arguments as written and of every criterion of its match, each
    /// kept apart from the next, so two arguments are never one with a space in it.
    public static func key(for rule: OpenerRule) -> String {
        // A command holds no control character (``OpenerRule/problem(in:)``), so these two cannot occur in a part.
        let parts =
            ["command"] + (rule.command ?? []) + ["\u{1}kind", rule.kind?.rawValue ?? "", "\u{1}extensions"]
            + (rule.extensions ?? []).map { $0.lowercased() } + [
                "\u{1}host", rule.host?.lowercased() ?? "", "\u{1}pattern", rule.pattern ?? ""
            ]
        return ProjectTrust.digest(Array(parts.joined(separator: "\u{0}").utf8))
    }

    public func allows(_ rule: OpenerRule) -> Bool { entries[Self.key(for: rule)] != nil }

    /// Allows `rule`'s command always, as it is written now.
    public mutating func allow(_ rule: OpenerRule) {
        entries[Self.key(for: rule)] = Grant(command: rule.command ?? [], match: rule.matchDescription)
    }

    /// Takes back what was allowed under `key`. Returns whether there was something.
    @discardableResult
    public mutating func revoke(_ key: String) -> Bool { entries.removeValue(forKey: key) != nil }

    /// What is allowed, by command, for a list a person reads.
    public var listing: [(key: String, grant: Grant)] {
        entries.map { (key: $0.key, grant: $0.value) }
            .sorted {
                ($0.grant.command.joined(separator: " "), $0.key) < ($1.grant.command.joined(separator: " "), $1.key)
            }
    }

    /// The store at `path`: empty when there is none. One that is there and cannot be read is an error, never "nothing allowed"
    /// passed off as the whole truth, nor, worse, a reason to ask nothing.
    public static func load(_ path: String) throws(ConfigurationError) -> OpenerGrants {
        var grants = OpenerGrants()
        grants.entries =
            try OwnerStore.load([String: Grant].self, from: path, what: "a store of allowed openers") ?? [:]
        return grants
    }

    /// Writes the store to `path`, the person's alone, replacing it atomically.
    public func save(to path: String) throws(ConfigurationError) { try OwnerStore.save(entries, to: path) }
}
