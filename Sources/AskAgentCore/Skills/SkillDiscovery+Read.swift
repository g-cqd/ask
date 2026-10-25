internal import CryptoKit
internal import Foundation

extension SkillDiscovery {
    struct Candidate {
        let file: String
        let directory: String
        /// The directory's name, or a bare file's name without `.md`: what a skill is called when its head does not say.
        let fallbackName: String
        let isBareFile: Bool
    }

    struct Failure: Error { let reason: String }

    /// Every skill file under `root`: a `SKILL.md` in a directory (any case), looked for through symlinked directories too and not inside another
    /// skill, and a bare Markdown file directly in the root.
    static func candidates(in root: String) -> [Candidate] {
        var found: [Candidate] = []
        var queue = [(root, 0)]
        var visited = 0
        while !queue.isEmpty, visited < maximumDirectories {
            let (directory, depth) = queue.removeFirst()
            visited += 1
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory).sorted() else { continue }
            if depth > 0, let skill = names.first(where: { $0.lowercased() == "skill.md" }) {
                found.append(
                    Candidate(
                        file: directory + "/" + skill, directory: directory,
                        fallbackName: (directory as NSString).lastPathComponent, isBareFile: false))
                continue
            }
            for name in names where name != ".git" && name != "node_modules" {
                let path = directory + "/" + name
                if isDirectory(path) {
                    if depth < maximumDepth { queue.append((path, depth + 1)) }
                } else if depth == 0, name.lowercased().hasSuffix(".md"), name.lowercased() != "readme.md" {
                    found.append(
                        Candidate(
                            file: path, directory: directory, fallbackName: String(name.dropLast(3)), isBareFile: true))
                }
            }
        }
        return found
    }

    static func read(_ candidate: Candidate, real: String, source: String, scope: SkillScope) -> Result<Skill, Failure>
    {
        guard let data = FileManager.default.contents(atPath: candidate.file) else {
            return .failure(Failure(reason: "could not be read"))
        }
        let bytes = [UInt8](data.prefix(maximumBytes))
        guard !bytes.contains(0) else { return .failure(Failure(reason: "is not text")) }
        let head = Self.readHead(bytes)
        var diagnostics = head.diagnostics
        if candidate.isBareFile, head.text("description") == nil {
            return .failure(Failure(reason: "a bare Markdown file with no description is not a skill"))
        }
        let name = head.text("name") ?? candidate.fallbackName
        guard let description = head.text("description") ?? derivedDescription(head.body) else {
            return .failure(Failure(reason: "has no description and nothing to take one from"))
        }
        if head.text("description") == nil { diagnostics.append("no description; the first line of the body is used") }
        diagnostics += nameDiagnostics(name, directory: candidate.fallbackName, isBare: candidate.isBareFile)
        let tools = ToolReference.parse(head.value("allowed-tools")) + ToolReference.parse(head.value("tools"))
        let unknown = tools.filter { $0.ask == nil }.map(\.token)
        if !unknown.isEmpty {
            diagnostics.append("tools ask does not know (kept, and grant nothing): \(unknown.joined(separator: ", "))")
        }
        if description.count > Skill.advertisedDescriptionLimit {
            diagnostics.append(
                "the description is \(description.count) characters; the advertisement cuts it at \(Skill.advertisedDescriptionLimit)"
            )
        }
        let known: Set<String> = [
            "name", "description", "allowedtools", "tools", "disallowedtools", "model", "models",
            "disablemodelinvocation"
        ]
        return .success(
            Skill(
                name: name, description: description, file: candidate.file, realFile: real,
                directory: URL(fileURLWithPath: real).deletingLastPathComponent().path, source: source, scope: scope,
                modelInvocable: !isTrue(head.text("disable-model-invocation")), tools: tools,
                disallowedTools: ToolReference.parse(head.value("disallowed-tools")), models: ModelPreference(head),
                otherKeys: head.entries.map(\.key).filter { !known.contains($0.canonicalKey) },
                diagnostics: diagnostics, digest: ProjectTrust.digest(bytes)))
    }

    /// The file read for its head. A skill's body is never needed to find it, so only the first `headBytes` are read as text; a head that does not end
    /// within them is read again whole. (Reading every body as lines was most of the time discovery took.)
    static func readHead(_ bytes: [UInt8]) -> DefinitionFile {
        guard bytes.count > headBytes else { return DefinitionFile(parsing: String(decoding: bytes, as: UTF8.self)) }
        let head = DefinitionFile(parsing: String(decoding: bytes.prefix(headBytes), as: UTF8.self))
        return head.isUnterminated ? DefinitionFile(parsing: String(decoding: bytes, as: UTF8.self)) : head
    }

    private static func isTrue(_ text: String?) -> Bool {
        guard let text else { return false }
        return ["true", "yes", "1", "on"].contains(text.lowercased())
    }

    /// The first paragraph of the body (a heading is skipped, and used only if there is no paragraph), cut to a sentence's worth, for a skill whose
    /// head gives no description.
    static func derivedDescription(_ body: String) -> String? {
        var paragraph: [String] = []
        var title: String?
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line).trimming(["#", " ", "\t", "*", "_"])
            if text.isEmpty {
                if !paragraph.isEmpty { break }
                continue
            }
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("#") {
                title = title ?? text
                if !paragraph.isEmpty { break }
                continue
            }
            paragraph.append(text)
        }
        let joined = paragraph.isEmpty ? (title ?? "") : paragraph.joined(separator: " ")
        return joined.isEmpty ? nil : String(joined.prefix(300))
    }

    /// Notes on a name that other harnesses would refuse. ask loads it anyway.
    private static func nameDiagnostics(_ name: String, directory: String, isBare: Bool) -> [String] {
        var notes: [String] = []
        let valid =
            !name.isEmpty && name.count <= 64
            && name.allSatisfy { ($0.isASCII && ($0.isLowercase || $0.isNumber)) || $0 == "-" }
            && !name.hasPrefix("-") && !name.hasSuffix("-") && !name.contains("--")
        if !valid {
            notes.append(
                "the name \"\(name)\" is outside the Agent Skills form (lower-case letters, digits and single hyphens, 64 at most)"
            )
        }
        if !isBare, name != directory {
            notes.append("the name \"\(name)\" differs from its directory \"\(directory)\"")
        }
        return notes
    }
}
