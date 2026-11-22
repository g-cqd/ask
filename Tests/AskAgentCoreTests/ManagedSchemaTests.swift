import AemiJSON
import Darwin
import Foundation
import Testing

@testable import AskAgentCore

/// What MDM consoles are given (ADR-0168, phase 4) agrees with what ask reads: each key's JSON types are the ones its reader takes, a
/// generated profile reads back as the JSON it was made from, and both schemas list every key.
@Suite("Console schemas and profiles")
struct ManagedSchemaTests {
    /// A value of each JSON type that a key of `row`'s shape could take, its example and choices first.
    private func candidates(_ row: SettingCatalog.Setting, _ type: ManagedSchema.JSONType) -> [String] {
        let words: [String] = if case .choice(let words) = row.kind { words.map { "\"\($0)\"" } } else { [] }
        let all =
            [row.example] + words + [
                "true", "false", "1", "3", "20", "200", "32768", "0", "0.5", "0.75", #""workspace""#, #""x""#,
                #"["x"]"#, "[]", "{}", "null"
            ]
        return all.filter { value in
            let first = value.first
            return switch type {
                case .boolean: value == "true" || value == "false"
                case .integer: Int(value) != nil
                case .number: Double(value) != nil && Int(value) == nil
                case .string: first == "\""
                case .array: first == "["
                case .object: first == "{"
                case .null: value == "null"
            }
        }
    }

    @Test func `each key's types are exactly those ask's reader takes`() throws {
        for key in try ManagedSchema.keys(SettingCatalog.all + SettingCatalog.managedOnly) {
            let row = try #require((SettingCatalog.all + SettingCatalog.managedOnly).first { $0.path == key.path })
            let read = ManagedSchema.JSONType.allCases.filter { type in
                candidates(row, type)
                    .contains { value in
                        var json = value
                        for name in key.path.reversed() { json = "{\"\(name)\": \(json)}" }
                        return (try? ConfigurationFile.parse(Array(json.utf8), path: "p")) != nil
                    }
            }
            #expect(Set(key.types) == Set(read), "\(key.title): declared \(key.types), read \(read)")
        }
    }

    private static let requirements = #"""
        {
          // comments, as config.json takes them
          "model": "team-model", "compactAt": 0.5, "maxTurns": 40,
          "sandbox": {"write": ["~/work"], "network": "provider"},
          "environment": {"withhold": ["CORP_*"]}, "ui": {"tint": false, "fold": {"codeLines": 30}},
          "policy": {"allowYes": false, "models": ["team-*"]}
        }
        """#
    private static let defaults = #"{"thinking": "high", "codemode": false}"#

    @Test func `a generated profile reads back as the JSON it was made from`() throws {
        let profile = try ManagedSchema.profile(
            requirements: Array(Self.requirements.utf8),
            defaults: Array(Self.defaults.utf8),
            identifier: "com.example.ask",
            organization: "Example"
        )
        let top = try #require(
            try PropertyListSerialization.propertyList(from: Data(profile), format: nil) as? [String: Any]
        )
        #expect(top["PayloadType"] as? String == "Configuration")
        let payload = try #require((top["PayloadContent"] as? [[String: Any]])?.first)
        #expect(payload["PayloadType"] as? String == "com.apple.ManagedClient.preferences")
        let domain = try #require(
            (payload["PayloadContent"] as? [String: Any])?[ManagedProfile.domain] as? [String: Any]
        )
        let settings = try #require(
            (domain["Forced"] as? [[String: Any]])?.first?["mcx_preference_settings"] as? [String: Any]
        )
        // What macOS writes to /Library/Managed Preferences from it, read by ask as a managed Mac would.
        let folder = FileManager.default.temporaryDirectory.appending(path: "ask-schema-\(UUID().uuidString)").path
        defer { try? FileManager.default.removeItem(atPath: folder) }
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: settings, format: .xml, options: 0)
            .write(to: URL(filePath: folder + "/" + ManagedProfile.domain + ".plist"))
        let profileReader = ManagedProfile(directory: folder, user: "nobody", owner: getuid())
        let fromProfile = try #require(try profileReader.load(.requirements).first?.file)
        let fromJSON = try ConfigurationFile.parse(Array(Self.requirements.utf8), path: "json")
        #expect(fromProfile.keysSet == fromJSON.keysSet)
        let applied = Configuration.defaults.applying(fromProfile, from: .defaults)
        let expected = Configuration.defaults.applying(fromJSON, from: .defaults)
        #expect(applied.model.value == expected.model.value && applied.compactAt.value == expected.compactAt.value)
        #expect(applied.sandbox.value == expected.sandbox.value && applied.ui.value == expected.ui.value)
        #expect(applied.policy.value == expected.policy.value && applied.maxTurns.value == expected.maxTurns.value)
        #expect(try profileReader.load(.defaults).first?.file.codemode == false)
    }

    @Test func `a profile ask would refuse is not written`() {
        let make = { (requirements: String?, defaults: String?) throws in
            _ = try ManagedSchema.profile(
                requirements: requirements.map { Array($0.utf8) },
                defaults: defaults.map { Array($0.utf8) },
                identifier: "com.example.ask",
                organization: "Example"
            )
        }
        #expect(throws: ConfigurationError.self) { try make(#"{"modle": "x"}"#, nil) }
        #expect(throws: ConfigurationError.self) { try make(nil, #"{"policy": {"allowYes": false}}"#) }
        #expect(throws: ConfigurationError.self) { try make(#"{"maxTurns": null}"#, nil) }
        #expect(throws: Never.self) { try make(nil, #"{"maxTurns": 10}"#) }
    }

    /// The keys a schema describes, by path, with their JSON types.
    private func leaves(_ object: [String: Any], _ prefix: [String] = []) -> [String: Any] {
        var found: [String: Any] = [:]
        for (name, value) in (object["properties"] as? [String: Any]) ?? [:] {
            guard let property = value as? [String: Any] else { continue }
            if property["type"] as? String == "object", property["properties"] != nil {
                found.merge(leaves(property, prefix + [name])) { first, _ in first }
            } else {
                found[(prefix + [name]).joined(separator: ".")] = property["type"]
            }
        }
        return found
    }

    @Test
    func `the Jamf schema lists every key in both documents, policy in requirements only, typed as the reader takes`()
        throws
    {
        let schema = try #require(try JSONSerialization.jsonObject(with: Data(ManagedSchema.jamf())) as? [String: Any])
        let documents = try #require(schema["properties"] as? [String: Any])
        let required = leaves(try #require(documents["requirements"] as? [String: Any]))
        let suggested = leaves(try #require(documents["defaults"] as? [String: Any]))
        let everyone = Set(SettingCatalog.all.map { $0.path.joined(separator: ".") })
        let managed = Set(SettingCatalog.managedOnly.map { $0.path.joined(separator: ".") })
        #expect(Set(required.keys) == everyone.union(managed))
        #expect(Set(suggested.keys) == everyone)
        #expect(required["sandbox.write"] as? [String] == ["string", "array"])
        #expect(required["maxTurns"] as? String == "integer", "null cannot be sent in a profile")
        #expect(
            required["ui.tint"] as? String == "boolean" && required["compactAt"] as? [String] == ["number", "integer"]
        )
    }

    @Test func `the manifest is a property list for the domain, with every key`() throws {
        let bytes = try ManagedSchema.manifest(modified: Date(timeIntervalSince1970: 0))
        let manifest = try #require(
            try PropertyListSerialization.propertyList(from: Data(bytes), format: nil) as? [String: Any]
        )
        #expect(manifest["pfm_domain"] as? String == ManagedProfile.domain)
        func names(_ subkeys: [[String: Any]], _ prefix: [String] = []) -> [String] {
            subkeys.flatMap { entry -> [String] in
                guard let name = entry["pfm_name"] as? String else { return [] }
                if entry["pfm_type"] as? String == "dictionary", let inner = entry["pfm_subkeys"] as? [[String: Any]] {
                    return names(inner, prefix + [name])
                }
                return [(prefix + [name]).joined(separator: ".")]
            }
        }
        let documents = try #require(manifest["pfm_subkeys"] as? [[String: Any]])
        let all = Set(names(documents))
        let everyone = SettingCatalog.all.map { $0.path.joined(separator: ".") }
        #expect(
            all
                == Set(
                    everyone.map { "defaults." + $0 }
                        + (everyone + PolicySection.keys.map { "policy." + $0 }).map { "requirements." + $0 }
                )
        )
    }
}
