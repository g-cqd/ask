internal import Foundation

/// Where agent definitions are found (roadmap 0063 phase 3): bare Markdown files in each root, the first root's definition of a name
/// winning; a README is not one, and a file larger than a skill may be is not read.
public enum AgentDiscovery {
    public static func definitions(in roots: [String]) -> [AgentDefinition] {
        var found: [AgentDefinition] = []
        var names: Set<String> = []
        for root in roots {
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for entry in entries.sorted() where entry.lowercased().hasSuffix(".md") && entry.lowercased() != "readme.md"
            {
                let file = root + "/" + entry
                guard let data = FileManager.default.contents(atPath: file), data.count <= SkillDiscovery.maximumBytes,
                    !data.contains(0),
                    let definition = AgentDefinition.read(file: file, text: String(decoding: data, as: UTF8.self)),
                    names.insert(definition.name).inserted
                else { continue }
                found.append(definition)
            }
        }
        return found
    }
}
