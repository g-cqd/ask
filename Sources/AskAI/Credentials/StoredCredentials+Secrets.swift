/// Which fields of each record are secrets (roadmap 0110): tokens and keys, never the metadata beside them. A record kept in a secret
/// store has ``marker`` in place of each secret in the file.
extension StoredCredentials {
    /// What the file holds where a secret is kept in the secret store.
    static let marker = "ask:keychain"

    /// The names of the records present: `claude`, `codex`, `agy`, `copilot`, and `keys.<provider>` for each key.
    var recordNames: [String] {
        [
            claude.map { _ in "claude" }, codex.map { _ in "codex" }, agy.map { _ in "agy" },
            copilot.map { _ in "copilot" }
        ]
        .compactMap { $0 } + (keys ?? [:]).keys.sorted().map { "keys." + $0 }
    }

    /// The secret fields of record `name`, as stored now (real values or markers); nil when there is no such record.
    func secrets(of name: String) -> [String: String]? {
        switch name {
            case "claude": return claude.map { ["accessToken": $0.accessToken, "refreshToken": $0.refreshToken] }
            case "codex": return codex.map { ["accessToken": $0.accessToken, "refreshToken": $0.refreshToken] }
            case "agy":
                return agy.map { record in
                    var fields = ["accessToken": record.accessToken, "refreshToken": record.refreshToken]
                    if let secret = record.clientSecret { fields["clientSecret"] = secret }
                    return fields
                }
            case "copilot": return copilot.map { ["githubToken": $0.githubToken, "accessToken": $0.accessToken] }
            default:
                guard name.hasPrefix("keys.") else { return nil }
                return keys?[String(name.dropFirst(5))].map { ["key": $0.key] }
        }
    }

    /// Replaces the secret fields of record `name` with `fields`; a field `fields` lacks is left as it is.
    mutating func setSecrets(_ fields: [String: String], of name: String) {
        func set(_ value: inout String, _ field: String) { if let new = fields[field] { value = new } }
        switch name {
            case "claude":
                set(&claude!.accessToken, "accessToken")
                set(&claude!.refreshToken, "refreshToken")
            case "codex":
                set(&codex!.accessToken, "accessToken")
                set(&codex!.refreshToken, "refreshToken")
            case "agy":
                set(&agy!.accessToken, "accessToken")
                set(&agy!.refreshToken, "refreshToken")
                if agy?.clientSecret != nil, let secret = fields["clientSecret"] { agy?.clientSecret = secret }
            case "copilot":
                set(&copilot!.githubToken, "githubToken")
                set(&copilot!.accessToken, "accessToken")
            default:
                let provider = String(name.dropFirst(5))
                guard name.hasPrefix("keys."), let key = fields["key"] else { return }
                keys?[provider]?.key = key
        }
    }

    /// The records whose secrets the file keeps in the secret store.
    var markedRecords: Set<String> {
        Set(recordNames.filter { name in secrets(of: name)?.values.contains(Self.marker) == true })
    }

    /// The records that hold at least one secret in the file itself.
    var inlineRecords: Set<String> {
        Set(recordNames.filter { name in secrets(of: name)?.values.contains { $0 != Self.marker } == true })
    }
}
