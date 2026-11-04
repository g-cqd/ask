internal import Foundation

/// `/skill:name [--from harnesses] request`, the user asking for a skill by name: what it becomes, and how it is shown afterwards.
///
/// The model gets one user message: the line as typed, then the skill, set off by a marker line. The session records that message, so a resume replays what
/// the model saw and the prompt cache sees the same bytes; every place that shows a prompt to a person cuts it at the marker (`shown`), so they see
/// the line they typed and not the skill's body.
public enum SkillInvocation {
    /// What a line asking for a skill comes to.
    public enum Expansion: Sendable, Equatable {
        /// The message to send the model.
        case prompt(String)
        /// Why nothing was sent.
        case failure(String)
        /// The line does not ask for a skill.
        case notASkill
    }

    /// The marker that ends what the user typed and starts the skill.
    public static let marker = "\n\n--- skill "

    public static let prefix = "/skill:"

    /// Whether `line` names a skill at the start of any word (roadmap 0185), so a caller can skip discovery for every other prompt.
    public static func asksForSkill(_ line: String) -> Bool { !inlineNames(line.trimmingWhitespace()).isEmpty }

    /// Reads `line` and attaches the skills it names: the line as typed, then each skill once, in the order named. A line that starts
    /// with `/skill:name` is an invocation, refused when the name is unknown; the user asked, so a skill that asked not to be offered to
    /// the model is still loaded, and `--from` names harnesses (or `bundled`) to look in, as the tool's `from` does. A `/skill:name` that
    /// starts a later word attaches the skill too (roadmap 0185); an unknown one there stays text.
    public static func expand(_ line: String, catalog: SkillCatalog, knownSources: [String]) -> Expansion {
        let typed = line.trimmingWhitespace()
        var first = Substring(typed)
        var sections: [String] = []
        var named: Set<String> = []
        if typed.hasPrefix(prefix) {
            switch leading(typed, catalog: catalog, knownSources: knownSources) {
                case .failure(let reason): return .failure(reason)
                case .attached(let skill, let section, let bare):
                    sections.append(section)
                    named.insert(skill)
                    if bare { first = typed.prefix { !$0.isWhitespace } }
            }
        }
        let selection = SkillSelection(tokens: [], knownSources: knownSources)
        for name in inlineNames(typed).dropFirst(typed.hasPrefix(prefix) ? 1 : 0) {
            let skill: Skill
            switch catalog.find(name, selection: selection) {
                case .found(let found), .onlyWhenAsked(let found): skill = found
                case .missing: continue
            }
            guard named.insert(skill.name).inserted, let contents = try? SkillContents.load(skill, note: inlineNote)
            else { continue }
            sections.append(section(skill, contents))
        }
        return sections.isEmpty ? .notASkill : .prompt(first + sections.joined())
    }

    private enum Leading {
        case attached(String, section: String, bare: Bool)
        case failure(String)
    }

    /// The invocation a line starts with: its skill, or why there is none.
    private static func leading(_ typed: String, catalog: SkillCatalog, knownSources: [String]) -> Leading {
        let word = typed.prefix { !$0.isWhitespace }
        let name = String(word.dropFirst(prefix.count))
        var request = String(typed.dropFirst(word.count)).trimmingWhitespace()
        var from: [String] = []
        if request.hasPrefix("--from"), request.dropFirst(6).first?.isWhitespace ?? true {
            let rest = request.dropFirst(6).drop { $0.isWhitespace }
            let list = rest.prefix { !$0.isWhitespace }
            from = list.split(separator: ",").map(String.init)
            request = String(rest.dropFirst(list.count)).trimmingWhitespace()
        }
        let skill: Skill
        switch catalog.find(name, selection: SkillSelection(tokens: from, knownSources: knownSources)) {
            case .found(let found), .onlyWhenAsked(let found): skill = found
            case .missing(let suggestions): return .failure(missing(name, suggestions, catalog))
        }
        let note =
            "The user invoked this skill by name. Follow it for the request above; if there is no request, begin the work it describes."
        do {
            return .attached(
                skill.name,
                section: section(skill, try SkillContents.load(skill, note: note)),
                bare: request.isEmpty
            )
        } catch {
            return .failure(error.reason)
        }
    }

    private static func missing(_ name: String, _ suggestions: [String], _ catalog: SkillCatalog) -> String {
        if let waiting = catalog.untrustedSkill(named: name) {
            let why = waiting.standing == .changed ? "has changed since you trusted it" : "is not trusted"
            return
                "The project skill \"\(waiting.skill.name)\" \(why), so it is not loaded. Look at \(waiting.skill.file), then run "
                + "ask trust --skills in a terminal."
        }
        let hint =
            suggestions.isEmpty ? "No skills are available." : "Available: \(suggestions.joined(separator: ", "))."
        return "No skill is called \"\(name)\". \(hint)"
    }

    private static let inlineNote =
        "The user named this skill in their message. Follow it for the part of the request it bears on."

    private static func section(_ skill: Skill, _ contents: String) -> String {
        "\(marker)\(skill.name) (\(skill.source), \(skill.scope.rawValue)) ---\n\(contents)\n--- end of skill ---"
    }

    /// The names after `/skill:` at the start of a word (after the line's start or white space), in order. A `/` inside a word (a
    /// path, an address) names nothing.
    static func inlineNames(_ text: String) -> [String] {
        var names: [String] = []
        var previous: Character = " "
        var index = text.startIndex
        while index < text.endIndex {
            if previous.isWhitespace, text[index...].hasPrefix(prefix) {
                let word = text[index...].prefix { !$0.isWhitespace }
                // Punctuation after a name (`/skill:debugging,`) is ignored by the catalog's lookup, as in any name.
                let name = word.dropFirst(prefix.count)
                if !name.isEmpty { names.append(String(name)) }
                index = text.index(index, offsetBy: word.count)
                previous = word.last ?? " "
                continue
            }
            previous = text[index]
            index = text.index(after: index)
        }
        return names
    }

    /// What a person is shown for a recorded prompt: everything before the first attachment, which is the line they typed.
    public static func shown(_ prompt: String) -> String {
        // The earliest attachment: a skill's, a task's or an idea's (0186), or a server's resource (0067).
        let cuts = [
            marker, ListReferences.taskMarker, ListReferences.ideaMarker, ResourceReferences.marker,
            ListReferences.threadMarker
        ]
        .compactMap { prompt.range(of: $0)?.lowerBound }
        guard let cut = cuts.min() else { return prompt }
        return String(prompt[..<cut])
    }
}
