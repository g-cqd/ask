/// A section's settings in one line, as a file names them: `inputRows 4, fold.tools false`, or `defaults` when it sets none.
enum SectionText {
    static func describe(_ keys: [String], _ value: (String) -> String?) -> String {
        let parts = keys.compactMap { key in value(key).map { "\(key) \($0)" } }
        return parts.isEmpty ? "defaults" : parts.joined(separator: ", ")
    }
}
