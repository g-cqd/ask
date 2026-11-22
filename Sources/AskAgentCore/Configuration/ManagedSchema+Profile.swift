internal import AemiJSON
public import Foundation

extension ManagedSchema {
    /// A configuration profile (`.mobileconfig`) that gives ask `requirements` and `defaults` (ADR-0168): a managed-preferences payload
    /// (`com.apple.ManagedClient.preferences`) forcing the domain `studio.aemi.ask`, in the shape Apple's Device Management documents.
    /// Each document is checked by ask's own reader first, so a profile that would stop ask on a managed Mac is never written.
    /// `identifier` names the profile (`com.example.ask`), `organization` its sender; `uuid` makes the identifiers unique.
    public static func profile(
        requirements: [UInt8]?,
        defaults: [UInt8]?,
        identifier: String,
        organization: String,
        uuid: () -> UUID = UUID.init
    ) throws -> [UInt8] {
        var settings: [String: Any] = [:]
        for (kind, bytes) in [(ManagedFiles.Kind.requirements, requirements), (.defaults, defaults)] {
            guard let bytes else { continue }
            let file = try ConfigurationFile.parse(bytes, path: kind.rawValue + ".json")
            if kind == .defaults, file.policy != nil {
                throw ConfigurationError.outOfRange(
                    path: "defaults.json",
                    key: "policy",
                    reason: "belongs in requirements.json only"
                )
            }
            let document = try AemiJSON.parse(
                bytes,
                options: JSONParseOptions(validation: .json5, duplicateKeys: .throwError)
            )
            settings[kind.rawValue] = try plist(JSONValue(document.root), at: "", in: kind.rawValue + ".json")
        }
        let payload: [String: Any] = [
            "PayloadType": "com.apple.ManagedClient.preferences",
            "PayloadVersion": 1,
            "PayloadIdentifier": identifier + ".preferences",
            "PayloadUUID": uuid().uuidString,
            "PayloadDisplayName": "ask",
            "PayloadContent": [ManagedProfile.domain: ["Forced": [["mcx_preference_settings": settings]]]]
        ]
        let profile: [String: Any] = [
            "PayloadType": "Configuration",
            "PayloadVersion": 1,
            "PayloadIdentifier": identifier,
            "PayloadUUID": uuid().uuidString,
            "PayloadDisplayName": "ask settings",
            "PayloadOrganization": organization,
            "PayloadScope": "System",
            "PayloadContent": [payload]
        ]
        return [UInt8](try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0))
    }

    /// A JSON value as a property-list value. A property list has no null, so a `null` (no limit) cannot be sent in a profile: it is
    /// refused with its key, for requirements.json or defaults.json to carry instead.
    private static func plist(_ value: JSONValue, at name: String, in file: String) throws(ConfigurationError) -> Any {
        switch value {
            case .bool(let flag): return flag
            case .int(let number): return number
            case .number(let number): return number
            case .string(let text): return text
            case .array(let items):
                var list: [Any] = []
                for (index, item) in items.enumerated() {
                    list.append(try plist(item, at: "\(name)[\(index)]", in: file))
                }
                return list
            case .object(let object):
                var dictionary: [String: Any] = [:]
                for (key, item) in object {
                    dictionary[key] = try plist(item, at: name.isEmpty ? key : name + "." + key, in: file)
                }
                return dictionary
            default:
                throw .outOfRange(
                    path: file,
                    key: name,
                    reason: "is null, which a profile cannot carry: write it in requirements.json or defaults.json"
                )
        }
    }
}
