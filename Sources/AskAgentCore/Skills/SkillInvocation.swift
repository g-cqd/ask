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

    /// Whether `line` starts as an invocation, so a caller can skip discovery for every other prompt.
    public static func asksForSkill(_ line: String) -> Bool { line.trimmingWhitespace().hasPrefix(prefix) }

    /// Reads `line` and, if it asks for a skill, looks the skill up. The user asked, so a skill that asked not to be offered to the model is still
    /// loaded; `--from` names harnesses (or `bundled`) to look in, as the tool's `from` does.
    public static func expand(_ line: String, catalog: SkillCatalog, knownSources: [String]) -> Expansion {
        let typed = line.trimmingWhitespace()
        guard typed.hasPrefix(prefix) else { return .notASkill }
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
        let selection = SkillSelection(tokens: from, knownSources: knownSources)
        let skill: Skill
        switch catalog.find(name, selection: selection) {
            case .found(let found), .onlyWhenAsked(let found): skill = found
            case .missing(let suggestions):
                if let waiting = catalog.untrustedSkill(named: name) {
                    let why = waiting.standing == .changed ? "has changed since you trusted it" : "is not trusted"
                    return .failure(
                        "The project skill \"\(waiting.skill.name)\" \(why), so it is not loaded. Look at \(waiting.skill.file), then run ask trust --skills in a terminal."
                    )
                }
                let hint =
                    suggestions.isEmpty
                    ? "No skills are available." : "Available: \(suggestions.joined(separator: ", "))."
                return .failure("No skill is called \"\(name)\". \(hint)")
        }
        let note =
            "The user invoked this skill by name. Follow it for the request above; if there is no request, begin the work it describes."
        let contents: String
        do { contents = try SkillContents.load(skill, note: note) } catch { return .failure(error.reason) }
        let first = request.isEmpty ? typed.prefix(while: { !$0.isWhitespace }) : Substring(typed)
        return .prompt(
            "\(first)\(marker)\(skill.name) (\(skill.source), \(skill.scope.rawValue)) ---\n\(contents)\n--- end of skill ---"
        )
    }

    /// What a person is shown for a recorded prompt: everything before the skill, which is the line they typed.
    public static func shown(_ prompt: String) -> String {
        guard let marker = prompt.range(of: marker) else { return prompt }
        return String(prompt[..<marker.lowerBound])
    }
}
