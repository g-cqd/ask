internal import AemiJSON
internal import Foundation

/// One configuration file as an interactive editor sees it: raw enough to preserve settings it
/// does not edit, typed enough to refuse a value ask would refuse. JSON5 in, strict JSON out.
public struct ConfigEditor: Sendable {
    public enum Scope: String, Sendable, Equatable, CaseIterable {
        case user, project
    }

    /// A staged editor value. `unset` removes the key rather than writing JSON null.
    public enum Value: Sendable, Equatable {
        case unset
        case bool(Bool)
        case string(String)
    }

    /// How a setting is stored: some switches are JSON booleans, the older UI switches are `"on"`/`"off"` strings.
    public enum Wire: Sendable, Equatable {
        case boolean, string
    }

    public struct Setting: Sendable, Equatable {
        public let path: [String]
        public let title: String
        public let value: String
        public let choices: [String]
        public let editable: Bool
        public let wire: Wire

        public init(
            path: [String], title: String, value: String, choices: [String] = [], editable: Bool = false,
            wire: Wire = .string
        ) {
            self.path = path
            self.title = title
            self.value = value
            self.choices = choices
            self.editable = editable
            self.wire = wire
        }
    }

    /// Why a commit failed: either ask refused the value, or the file could not be replaced.
    public enum Error: Swift.Error, Sendable, Equatable, CustomStringConvertible {
        case configuration(ConfigurationError)
        case cannotWrite(path: String, reason: String)

        public var description: String {
            switch self {
                case .configuration(let error): String(describing: error)
                case .cannotWrite(let path, let reason): "\(path): \(reason)"
            }
        }
    }

    /// One row the editor can show: its key path, how its value is written, and what it may become.
    struct Descriptor: Sendable, Equatable {
        enum Kind: Sendable, Equatable {
            case boolean, onOff
            case choice([String])
            case readOnly
        }

        let path: [String]
        let kind: Kind
    }

    public let path: String
    public let isProject: Bool
    public let scope: Scope
    public let fileExists: Bool
    public let warnings: [String]

    var root: JSONValue
    let bytes: [UInt8]?
    let pretty: Bool
    let indent: String
    let foundationSeparator: Bool
    let trailingNewline: Bool

    public init(path: String, isProject: Bool) throws(ConfigurationError) {
        self.path = path
        self.isProject = isProject
        scope = isProject ? .project : .user
        let bytes = try ConfigurationFileReader.read(path)
        self.bytes = bytes
        fileExists = bytes != nil
        root = .object([:])
        guard let bytes else {
            pretty = false
            indent = "  "
            foundationSeparator = false
            trailingNewline = true
            warnings = []
            return
        }
        let document: JSONDocument
        do {
            document = try AemiJSON.parse(
                bytes, options: JSONParseOptions(validation: .json5, duplicateKeys: .throwError))
        } catch {
            let position = ConfigurationFile.position(of: error, in: bytes)
            throw ConfigurationError.invalid(
                path: path, line: position.0, column: position.1,
                reason: ConfigurationFile.reason(of: error))
        }
        // Old setting names read as the new ones (roadmap 0154), so a save from here writes the new names.
        do {
            root = try SettingRenames.apply(to: JSONValue(document.root)).value
        } catch let bad as ConfigurationFile.BadValue {
            throw ConfigurationError.outOfRange(path: path, key: bad.key, reason: bad.reason)
        } catch {
            throw ConfigurationError.invalid(path: path, line: nil, column: nil, reason: String(describing: error))
        }
        let text = String(decoding: bytes, as: UTF8.self)
        let format = ConfigEditorFormat(of: text)
        pretty = format.pretty
        indent = format.indent
        foundationSeparator = format.foundationSeparator
        trailingNewline = format.trailingNewline
        let stripped = Self.stripped(root, path: [])
        warnings = stripped.warnings
        let strippedBytes: [UInt8]
        do {
            strippedBytes = try Self.encoding(
                of: stripped.value, pretty: false, indent: "", separator: .javaScript,
                trailingNewline: false)
        } catch {
            throw ConfigurationError.invalid(path: path, line: nil, column: nil, reason: String(describing: error))
        }
        _ = try ConfigurationFile.parse(strippedBytes, path: path, isProject: isProject)
    }

    /// The settings the editor exposes, in configuration order. Editable rows are booleans and enums;
    /// strings, numbers, paths, lists and whole sections are shown read-only so the editor never guesses.
    public var settings: [Setting] { Self.descriptors.compactMap { Self.setting($0, in: root) } }

    /// A setting by path, or nil when the path is not one the editor offers.
    public func setting(_ path: [String]) -> Setting? { settings.first { $0.path == path } }

    /// Parses the text a row shows into the typed value that key accepts.
    public func value(_ text: String, at path: [String]) throws(ConfigurationError) -> Value {
        guard let setting = setting(path) else {
            throw ConfigurationError.unknownKey(
                path: self.path, key: path.joined(separator: "."), known: ConfigurationFile.keys)
        }
        if text == "unset" { return .unset }
        guard setting.editable, setting.choices.contains(text) else {
            throw ConfigurationError.outOfRange(
                path: self.path, key: path.joined(separator: "."),
                reason: "must be one of: \(setting.choices.filter { $0 != "unset" }.joined(separator: ", "))")
        }
        if setting.wire == .boolean, setting.choices == ["unset", "on", "off"] { return .bool(text == "on") }
        return .string(text)
    }
}
