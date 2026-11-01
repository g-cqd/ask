internal import AskAgentCore

/// A tool's input refused before anything ran (ADR-0141): the field, the change it is in, and what was expected, in words the model can
/// act on.
struct ToolInputError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) { self.description = description }

    /// What an entry of `changes` says before its number is known; ``numbered(_:)`` gives it.
    static let entry = "change"

    /// Decodes `changes` one entry at a time, so a refusal says which: `change 3: …`.
    static func entries<Entry: Decodable>(
        _ container: KeyedDecodingContainer<RecordKey>,
        _ type: Entry.Type
    ) throws -> [Entry]? {
        guard container.contains(RecordKey("changes")) else { return nil }
        var list = try container.nestedUnkeyedContainer(forKey: RecordKey("changes"))
        var entries: [Entry] = []
        while !list.isAtEnd {
            let number = entries.count + 1
            do {
                entries.append(try list.decode(Entry.self))
            } catch let error as ToolInputError where error.description.hasPrefix(entry + ":") {
                throw ToolInputError("change \(number)" + error.description.dropFirst(entry.count))
            }
        }
        return entries
    }
}
