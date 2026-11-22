internal import AemiJSON
internal import CoreFoundation
internal import Foundation

/// The configuration profile an MDM installs for ask (roadmap 0130, ADR-0168, phase 3): its preference domain `studio.aemi.ask` holds
/// `requirements` and `defaults`, each a dictionary written like `config.json`. macOS keeps a profile's forced preferences for the
/// machine in `/Library/Managed Preferences/studio.aemi.ask.plist` and for a user in `/Library/Managed Preferences/<user>/`; ask reads
/// those files itself, and only the ones that exist, rather than through CFPreferences, whose first call costs 3.8 ms (research §1).
/// They are trusted as the files beside them are: root's, writable by no one else.
public struct ManagedProfile: Sendable, Equatable {
    /// ask's preference domain.
    public static let domain = "studio.aemi.ask"

    /// The system's: on macOS, where profiles exist; nil elsewhere.
    public static var system: ManagedProfile? {
        #if os(macOS)
            ManagedProfile(directory: "/Library/Managed Preferences", user: NSUserName(), owner: 0)
        #else
            nil
        #endif
    }

    public let directory: String
    public let user: String
    public let owner: UInt32

    public init(directory: String, user: String, owner: UInt32) {
        self.directory = directory
        self.user = user
        self.owner = owner
    }

    /// The `kind` dictionaries of the machine's profile, then the user's, as configuration files named `PLIST: kind`.
    func load(_ kind: ManagedFiles.Kind) throws(ConfigurationError) -> [(path: String, file: ConfigurationFile)] {
        var found: [(path: String, file: ConfigurationFile)] = []
        for plist in [directory + "/" + Self.domain + ".plist", directory + "/" + user + "/" + Self.domain + ".plist"]
        where FileManager.default.fileExists(atPath: plist) {
            try ManagedFiles.trust(plist, owner: owner)
            guard let bytes = try ConfigurationFileReader.read(plist) else { continue }
            guard let inner = try Self.dictionary(kind, in: bytes, at: plist) else { continue }
            let name = plist + ": " + kind.rawValue
            let json: [UInt8]
            do {
                json = try JSONValue.object(try Self.object(inner, at: name))
                    .encodedBytes(options: JSONEncodingOptions())
            } catch {
                throw .invalid(path: name, line: nil, column: nil, reason: "\(error)")
            }
            found.append((name, try ConfigurationFile.parse(json, path: name)))
        }
        return found
    }

    /// The `kind` dictionary of the profile in `bytes`, or nil when it holds none. Its other keys must be the other kind, or what
    /// macOS adds itself (`Payload…`, `_…`): any other is refused, so a misspelt `requirments` does not leave a machine unmanaged.
    private static func dictionary(_ kind: ManagedFiles.Kind, in bytes: [UInt8], at plist: String)
        throws(ConfigurationError)
        -> [String: Any]?
    {
        let root: Any
        do { root = try PropertyListSerialization.propertyList(from: Data(bytes), format: nil) } catch {
            throw .invalid(path: plist, line: nil, column: nil, reason: "is not a property list")
        }
        guard let top = root as? [String: Any] else {
            throw .invalid(path: plist, line: nil, column: nil, reason: "is not a dictionary")
        }
        let kinds = ManagedFiles.Kind.allCases.map(\.rawValue)
        for key in top.keys.sorted() where !kinds.contains(key) && !key.hasPrefix("Payload") && !key.hasPrefix("_") {
            throw .unknownKey(path: plist, key: key, known: kinds)
        }
        guard let value = top[kind.rawValue] else { return nil }
        guard let inner = value as? [String: Any] else {
            throw .invalid(path: plist, line: nil, column: nil, reason: "\"\(kind.rawValue)\" is not a dictionary")
        }
        return inner
    }

    /// A property list dictionary as JSON's object, its keys sorted.
    private static func object(_ dictionary: [String: Any], at name: String) throws(ConfigurationError)
        -> OrderedDictionary<String, JSONValue>
    {
        var object = OrderedDictionary<String, JSONValue>()
        for key in dictionary.keys.sorted() {
            if let value = dictionary[key] { object[key] = try json(value, at: name + "." + key) }
        }
        return object
    }

    /// A property list value as JSON: a dictionary, an array, text, a boolean or a number; a date or data has no JSON form.
    private static func json(_ value: Any, at name: String) throws(ConfigurationError) -> JSONValue {
        switch value {
            case let text as String: return .string(text)
            case let number as NSNumber:
                if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
                return CFNumberIsFloatType(number) ? .number(number.doubleValue) : .int(number.int64Value)
            case let list as [Any]:
                var items: [JSONValue] = []
                for (index, item) in list.enumerated() { items.append(try json(item, at: "\(name)[\(index)]")) }
                return .array(items)
            case let dictionary as [String: Any]: return .object(try object(dictionary, at: name))
            default:
                throw .invalid(
                    path: name,
                    line: nil,
                    column: nil,
                    reason: "holds a date or data, which a configuration does not take"
                )
        }
    }
}
