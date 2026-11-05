internal import AemiJSON
internal import Foundation

/// A definition's model word that ``ModelMatch`` cannot place, classified by a very cheap model on the connection (roadmap 0063 phase 4,
/// ADR-0146, on by default). It is given the word and the listed ids, nothing of the definition; its answer counts only when it is one
/// of those ids exactly, so it can choose among what is listed and never add to it; each connection's answer for a word is kept, a
/// "none" too, so a word is asked about once.
public enum ModelResolution {
    /// Words in a model's id that say it is a small, cheap one.
    static let cheapWords: Set<String> = ["haiku", "mini", "flash", "lite", "nano", "small"]

    /// The first listed model whose id says it is small; nil when none does, and then nothing is asked.
    public static func cheapModel(in listed: [String]) -> String? {
        listed.first { id in
            id.lowercased().split(whereSeparator: { "-._/:".contains($0) }).contains { cheapWords.contains(String($0)) }
        }
    }

    /// What the cheap model is asked: which listed id `word` names, if any.
    public static func question(word: String, listed: [String]) -> String {
        """
        A configuration file names a model as "\(word)". Which of these model ids does it mean? Reply with one of them exactly, or \
        with none if it means none of them. Reply with nothing else.

        \(listed.joined(separator: "\n"))
        """
    }

    /// The listed id `reply` is, after quotes, back quotes and a full stop; nil for anything else, `none` included.
    public static func answer(_ reply: String, listed: [String]) -> String? {
        let word = reply.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n\r\"'`."))
        return listed.first { $0 == word }
    }

    /// What was answered for each connection and word, in a file of the person's own.
    public struct Cache {
        let path: String
        var entries: [String: String]

        public init(path: String) {
            self.path = path
            let data = FileManager.default.contents(atPath: path) ?? Data()
            entries = (try? AemiJSON.JSONDecoder().decode([String: String].self, from: [UInt8](data))) ?? [:]
        }

        private static func key(_ provider: String, _ word: String) -> String { provider + "|" + word.lowercased() }

        /// nil: never asked; `.some(nil)`: asked, and nothing matched.
        public func answer(provider: String, word: String) -> String?? {
            entries[Self.key(provider, word)].map { $0.isEmpty ? nil : $0 }
        }

        /// Keeps `id` (nil for none) as the answer for `word` on `provider`, written at once and readable by the person alone.
        public mutating func keep(_ id: String?, provider: String, word: String) throws {
            entries[Self.key(provider, word)] = id ?? ""
            let data = Data(try AemiJSON.JSONEncoder().encodeToBytes(entries))
            try FileManager.default.createDirectory(
                atPath: (path as NSString).deletingLastPathComponent,
                withIntermediateDirectories: true
            )
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        }
    }
}
