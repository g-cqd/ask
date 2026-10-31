internal import AemiJSON

extension ConfigurationFile {
    /// A value of the wrong JSON type as the key it sits under, the value, and what the key takes (roadmap 0118), instead of the
    /// decoder's words; nil when the path is not a catalog setting or a section (an MCP server's member), left to the decoder's text.
    static func refusal(of error: any Error, in bytes: [UInt8], path: String) -> ConfigurationError? {
        let codingPath: [any CodingKey]
        switch error as? DecodingError {
            case .typeMismatch(_, let context), .valueNotFound(_, let context): codingPath = context.codingPath
            default: return nil
        }
        let names = codingPath.filter { $0.intValue == nil }.map(\.stringValue)
        let key = names.joined(separator: ".")
        let expected =
            SettingCatalog.setting(key)?.expected ?? (SettingCatalog.sections.contains(key) ? "an object" : nil)
        guard let expected else { return nil }
        let options = JSONParseOptions(validation: .json5, duplicateKeys: .throwError)
        let value = (try? AemiJSON.parse(bytes, options: options))
            .flatMap {
                ConfigEditor.value(at: names, in: JSONValue($0.root))
            }
        let shown =
            value.flatMap {
                try? ConfigEditor.encoding(
                    of: $0, pretty: false, indent: "", separator: .javaScript, trailingNewline: false)
            }
            .map { String(decoding: $0, as: UTF8.self) }
        return .outOfRange(path: path, key: key, reason: (shown.map { "is \($0): " } ?? "") + "use \(expected)")
    }
}
