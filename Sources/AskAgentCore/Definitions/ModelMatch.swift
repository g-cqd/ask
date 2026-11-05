/// A definition's model words matched against the models a connection lists (roadmap 0063 phase 3). Three ways, strictest first, for
/// each word in the file's order: the id itself (any case); a display name written another way (`Claude Opus 5.5` for
/// `claude-opus-5-5`: letters and digits only, any case); a family word that is a whole part of an id (`haiku`, the first such model
/// listed). A word that is only a part of another (`son`) names nothing: a model is never guessed.
public enum ModelMatch {
    /// The first listed model one of `words` names, in the words' order; nil when none does.
    public static func first(of words: [String], in listed: [String]) -> String? {
        for word in words {
            let lowered = word.lowercased()
            if let exact = listed.first(where: { $0.lowercased() == lowered }) { return exact }
            let squeezed = squeeze(word)
            if !squeezed.isEmpty, let named = listed.first(where: { squeeze($0) == squeezed }) { return named }
            if lowered.allSatisfy(\.isLetter),
                let family = listed.first(where: { parts($0).contains(lowered) })
            {
                return family
            }
        }
        return nil
    }

    /// Only the letters and digits, lowercased: what a display name and an id share.
    private static func squeeze(_ text: String) -> String {
        String(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    /// An id's parts: what dashes, dots, slashes and underscores separate.
    private static func parts(_ id: String) -> [String] {
        id.lowercased().split(whereSeparator: { "-._/:".contains($0) }).map(String.init)
    }
}
