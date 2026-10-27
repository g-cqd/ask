internal import AemiText

extension SkillCatalog {
    /// Searches metadata only; literal matches rank above bounded Levenshtein matches. Permission filters precede ranking.
    public func search(_ query: String, selection: SkillSelection, limit: Int = 8) -> [Skill] {
        let words = query.lowercased().split { !($0.isLetter || $0.isNumber) }.prefix(16).map(String.init)
        var seen = Set<String>()
        let pool = (skills + shadowed)
            .filter {
                guard selection.includes(source: $0.source, scope: $0.scope) else { return false }
                // A user-only winner must not expose a shadowed version of the same name by default.
                return seen.insert($0.name.lowercased()).inserted && $0.modelInvocable
            }
        let scored = pool.compactMap { skill -> (skill: Skill, literal: Int, fuzzy: Int)? in
            let name = skill.name.lowercased()
            let description = skill.description.lowercased()
            let nameTokens = Self.searchTokens(name)
            let descriptionTokens = Self.searchTokens(description)
            var literal = 0
            var fuzzy = 0
            for word in words {
                let score = (name.contains(word) ? 3 : 0) + (description.contains(word) ? 1 : 0)
                literal += score
                if score == 0 {
                    fuzzy += Swift.max(
                        Self.fuzzyScore(word, tokens: nameTokens) * 3,
                        Self.fuzzyScore(word, tokens: descriptionTokens))
                }
            }
            return words.isEmpty || literal > 0 || fuzzy > 0 ? (skill, literal, fuzzy) : nil
        }
        return
            scored.sorted {
                if $0.literal != $1.literal { return $0.literal > $1.literal }
                if $0.fuzzy != $1.fuzzy { return $0.fuzzy > $1.fuzzy }
                return ($0.skill.name.lowercased(), $0.skill.name) < ($1.skill.name.lowercased(), $1.skill.name)
            }
            .prefix(Swift.max(0, limit)).map(\.skill)
    }

    private static func searchTokens(_ text: String) -> [Substring] {
        Array(text.split { !($0.isLetter || $0.isNumber) }.prefix(128))
    }

    /// One edit for 3–5 characters, two for longer words. Short acronyms and huge tokens are literal-only.
    private static func fuzzyScore(_ word: String, tokens: [Substring]) -> Int {
        let count = word.count
        guard (3 ... 64).contains(count) else { return 0 }
        let bound = count >= 6 ? 2 : 1
        let characters = Array(word)
        var best = bound + 1
        for token in tokens where abs(token.count - count) <= bound {
            best = Swift.min(best, AemiText.editDistance(characters, Array(token), maxDistance: bound))
            if best == 0 { break }
        }
        return best <= bound ? bound + 1 - best : 0
    }
}
