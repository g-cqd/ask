/// The models a definition file asks for, in order of preference, as the words it used.
///
/// Files name models as one alias (`opus`), a list of display names (`["Claude Opus 5.5", "GPT-6 Astra"]`), or an alias with its fallbacks in a comment
/// (`# fallback_models: claude-opus-5-5, sonnet`, `# tier_models: [flash_lite, flash]`). This keeps the words, in order, without deciding what they
/// mean: matching them against the models a connection offers is separate, and when nothing matches the parent's model is used.
public struct ModelPreference: Sendable, Equatable {
    /// The preferred models, then the fallbacks, as written, without repeats.
    public let tokens: [String]
    /// Whether the file said to use the parent's model (`inherit`, `default`), or named no model at all.
    public let inheritsParent: Bool

    public init(tokens: [String], inheritsParent: Bool) {
        self.tokens = tokens
        self.inheritsParent = inheritsParent
    }

    /// The preference in `file`: its `model` field, then any comment hint whose key mentions models.
    public init(_ file: DefinitionFile) {
        var words = Self.words(in: file.value("model", "models"))
        for hint in file.hints where hint.key.canonicalKey.contains("model") { words += Self.words(in: hint.value) }
        var seen = Set<String>()
        var tokens: [String] = []
        var inherits = words.isEmpty
        for word in words {
            let key = word.lowercased()
            if ["inherit", "default", "parent", "same"].contains(key) {
                inherits = true
            } else if seen.insert(key).inserted {
                tokens.append(word)
            }
        }
        self.init(tokens: tokens, inheritsParent: inherits)
    }

    /// The names in a value. Unlike a tool list, a model name may hold spaces (`Claude Opus 5.5`), so only commas, semicolons, bars and line
    /// breaks separate them; anything in parentheses after them (`(effort = "low")`) is not a name.
    static func words(in value: DefinitionValue?) -> [String] {
        guard let value else { return [] }
        return value.scalars.flatMap { scalar in
            scalar.split(whereSeparator: { $0 == "," || $0 == ";" || $0 == "|" || $0 == "\n" })
                .compactMap { piece in
                    var word = String(piece).trimmingWhitespace()
                    if let paren = word.firstIndex(of: "(") { word = String(word[..<paren]).trimmingWhitespace() }
                    word = word.trimming(["[", "]", " "]).unquoted().trimmingWhitespace()
                    return word.isEmpty ? nil : word
                }
        }
    }
}
