internal import Foundation

/// A skill read from its file for the model: where it lives, then its body without its head. What the `skill` tool returns and what `/skill:name` sends.
public enum SkillContents {
    /// Why a skill could not be read.
    public struct Failure: Error, Sendable, Equatable {
        public let reason: String
    }

    /// The skill as the model reads it.
    ///
    /// A project's skill is read again here and must still be the file the user trusted: trust was decided when the skill was found, and the file is
    /// text from a repository that may have changed since (a `git pull`, or a tool of the model's own).
    /// - Parameters:
    ///   - skill: the skill to read, as discovery found it.
    ///   - note: an extra line for the header, such as why the skill was loaded.
    /// - Returns: the text.
    /// - Throws: ``Failure`` when the file cannot be read, or a project's skill has changed since it was found.
    public static func load(_ skill: Skill, note: String? = nil) throws(Failure) -> String {
        guard let data = FileManager.default.contents(atPath: skill.realFile) else {
            throw Failure(reason: "The skill \"\(skill.name)\" could not be read from \(skill.file).")
        }
        let bytes = [UInt8](data.prefix(SkillDiscovery.maximumBytes))
        if skill.scope == .project, ProjectTrust.digest(bytes) != skill.digest {
            throw Failure(
                reason:
                    "The skill \"\(skill.name)\" has changed since it was found, so it is not loaded. The user can look at it again and run ask trust --skills."
            )
        }
        let file = DefinitionFile(parsing: String(decoding: bytes, as: UTF8.self))
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
