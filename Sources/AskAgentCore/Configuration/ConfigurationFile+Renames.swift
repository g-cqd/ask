internal import AemiJSON

extension ConfigurationFile {
    /// `bytes` with the names roadmap 0154 replaced read as the new ones, and a sentence for each. A file without old names comes back
    /// as it was, so an error's line and column point into it; one that does not parse is left for the decoder to report.
    /// - Throws: ``BadValue`` for an old name whose value it never took.
    static func renamingOldNames(in bytes: [UInt8], path: String) throws -> ([UInt8], [String]) {
        let options = JSONParseOptions(validation: .json5, duplicateKeys: .throwError)
        guard let document = try? AemiJSON.parse(bytes, options: options) else { return (bytes, []) }
        let result = try SettingRenames.apply(to: JSONValue(document.root))
        guard !result.notices.isEmpty,
            let encoded = try? ConfigEditor.encoding(
                of: result.value, pretty: false, indent: "", separator: .javaScript, trailingNewline: false)
        else { return (bytes, []) }
        return (encoded, result.notices.map { "\(path): \($0)" })
    }
}
