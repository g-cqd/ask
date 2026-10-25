internal import Foundation

/// A skill read from its file for the model: where it lives, then its body without its head. What the `skill` tool returns and what `/skill:name` sends.
public enum SkillContents {
    /// The skill as the model reads it.
    /// - Parameters:
    ///   - skill: the skill to read, as discovery found it.
    ///   - note: an extra line for the header, such as why the skill was loaded.
    /// - Returns: the text, or nil when the file can no longer be read.
    public static func load(_ skill: Skill, note: String? = nil) -> String? {
        guard let data = FileManager.default.contents(atPath: skill.realFile) else { return nil }
        let file = DefinitionFile(parsing: String(decoding: data.prefix(SkillDiscovery.maximumBytes), as: UTF8.self))
        var header = [
            "Skill: \(skill.name) (\(skill.source), \(skill.scope.rawValue))", "Directory: \(skill.directory)"
        ]
        header.append(
            "Paths in these instructions are relative to that directory. Loading a skill grants no permission.")
        if let note { header.append(note) }
        let body = file.format == .none ? file.body : file.body.trimmingCharacters(in: .newlines)
        return header.joined(separator: "\n") + "\n\n" + body
    }
}
