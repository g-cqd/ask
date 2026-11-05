internal import Foundation

/// Where agent definitions are found (roadmap 0063 phase 3): bare Markdown files in each root, the first root's definition of a name
/// winning; a README is not one, and a file larger than a skill may be is not read.
public enum AgentDiscovery {
    /// The person's own definitions in `roots`, in order.
    public static func definitions(in roots: [String]) -> [AgentDefinition] {
        var names: Set<String> = []
        return roots.flatMap(read).filter { names.insert($0.name).inserted }
    }

    /// A project's definitions in `root`: those whose file, as its bytes are now, `trust` holds, and the rest. A project is text from a
    /// repository, so what it would have a subagent told counts only once the person has read and trusted it (`ask trust --agents`).
    public static func projectDefinitions(in root: String, trust: ProjectTrust) -> (
        trusted: [AgentDefinition], untrusted: [AgentDefinition]
    ) {
        var names: Set<String> = []
        let all = read(root).filter { names.insert($0.name).inserted }
        let trusted = all.filter { trust.standing(of: $0.realFile, digest: $0.digest) == .trusted }
        return (trusted, all.filter { trust.standing(of: $0.realFile, digest: $0.digest) != .trusted })
    }

    /// Every definition file directly in `root`, in name order, with its real path and digest.
    private static func read(_ root: String) -> [AgentDefinition] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else { return [] }
        return entries.sorted()
            .filter { $0.lowercased().hasSuffix(".md") && $0.lowercased() != "readme.md" }
            .compactMap { entry -> AgentDefinition? in
                let file = root + "/" + entry
                guard let data = FileManager.default.contents(atPath: file), data.count <= SkillDiscovery.maximumBytes,
                    !data.contains(0),
                    var definition = AgentDefinition.read(file: file, text: String(decoding: data, as: UTF8.self))
                else { return nil }
                definition.realFile = URL(fileURLWithPath: file).resolvingSymlinksInPath().path
                definition.digest = ProjectTrust.digest([UInt8](data))
                return definition
            }
    }
}
