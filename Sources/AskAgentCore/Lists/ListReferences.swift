/// `#t3` and `#n2` in a message (roadmap 0186): the task's line and description, or the note's text, attached after what was typed, as
/// a skill is (0185); each once, in the order named. Only a word that starts with `#` counts, and only the typed line is read for them
/// (not an attached skill); an id that is not there stays text.
public enum ListReferences {
    public static let taskMarker = "\n\n--- task "
    public static let ideaMarker = "\n\n--- note "
    /// What a thread's answer follows the person's next message under (roadmap 0194).
    public static let threadMarker = "\n\n--- thread "

    public static func attach(_ text: String, tasks: TaskList?, ideas: IdeaList?) -> String {
        let typed = SkillInvocation.shown(text)
        var sections: [String] = []
        var seen: Set<String> = []
        for ref in words(typed) where seen.insert(ref).inserted {
            guard let number = Int(ref.dropFirst()) else { continue }
            if ref.first == "t", let tasks, let shown = tasks.showing(number) {
                sections.append("\(taskMarker)t\(number) ---\n\(shown)\n--- end of task ---")
            } else if ref.first == "n" || ref.first == "i", let ideas, let idea = ideas.idea(number) {
                sections.append("\(ideaMarker)n\(number) ---\n\(idea.text)\n--- end of note ---")
            }
        }
        return text + sections.joined()
    }

    /// The `t3` and `n2` of each `#t3`, `#n2` that starts a word, in order; punctuation after it is not part of it.
    static func words(_ text: String) -> [String] {
        // `attach` reads the number; a word that is none (`#tx`) attaches nothing there.
        hashWords(in: text)
            .filter { word in
                guard let kind = word.first else { return false }
                return (kind == "t" || kind == "n" || kind == "i") && word.count > 1
            }
            .map(String.init)
    }

    /// The letters and digits after each `#` that starts a word in `text`, in order; for `#t3` and for `#123` (``ForgeReferences``).
    static func hashWords(in text: String) -> [Substring] {
        var found: [Substring] = []
        var previous: Character = " "
        for (index, character) in zip(text.indices, text) {
            defer { previous = character }
            guard character == "#", previous.isWhitespace else { continue }
            found.append(text[text.index(after: index)...].prefix { $0.isLetter || $0.isNumber })
        }
        return found
    }
}
