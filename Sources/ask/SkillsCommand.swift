// @dl:accept -- the commands share a shape
internal import ArgumentParser
internal import AskAgentCore
internal import Foundation

/// `ask skills`: the skills ask can see, from every harness's directories, and what it noticed about each (roadmap 0061).
struct SkillsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "skills",
        abstract: "List the skills found in every harness's directories, and anything odd about them.")

    @Option(
        name: .customLong("from"),
        help: ArgumentHelp(
            "Only these harnesses, separated by commas: \(SkillSource.ids.joined(separator: ", ")); user, project. Default: every harness's user and project skills.",
            valueName: "sources"))
    var from: String?

    @Flag(name: .shortAndLong, help: "Show each skill's tools, models and other fields, and the directories searched.")
    var verbose = false

    @Option(
        name: .customLong("inspect"), parsing: .upToNextOption,
        help: ArgumentHelp(
            "Show how these files are read (a skill, or any harness's agent definition) and stop.", valueName: "files"))
    var inspect: [String] = []

    func run() {
        if !inspect.isEmpty {
            for path in inspect {
                guard let data = FileManager.default.contents(atPath: path) else {
                    print("\(path): could not be read")
                    continue
                }
                for line in DefinitionReport(
                    path: path, text: String(decoding: data.prefix(SkillDiscovery.maximumBytes), as: UTF8.self)
                )
                .lines {
                    print(line)
                }
            }
            return
        }
        let tokens = (from ?? "").split(separator: ",").map(String.init)
        let selection = SkillSelection(tokens: tokens, knownSources: SkillSource.standard.map(\.id))
        let catalog = SkillDiscovery.discover(
            workingDirectory: FileManager.default.currentDirectoryPath, home: NSHomeDirectory(),
            sources: SkillSource.standard,
            selection: selection, trust: SkillBook.trust())
        for line in SkillReport(catalog: catalog, selection: selection, verbose: verbose).lines { print(line) }
    }
}
