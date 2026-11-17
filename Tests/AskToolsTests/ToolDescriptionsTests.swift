internal import AskAI
internal import AskAgentCore
internal import Foundation
internal import Testing

@testable import AskTools

/// What a model is told about each tool (ADR-0157): a first line saying what the tool is for, and for every argument, at any depth,
/// a phrase saying what it is. In the sessions read on 2026-11-17 one argument of 46 said anything, and the calls refused were the
/// ones whose limits were written nowhere a model reads when it writes the value.
@Suite("Every tool says what it is for in a line, and every argument says what it is")
struct ToolDescriptionsTests {
    /// Every tool ask declares for a model, but an MCP server's own tools, whose words are the server's.
    private static var declared: [ToolDefinition] {
        let jobs = JobTable()
        let catalog = MCPCatalog()
        return [
            ReadTool().definition, WriteTool().definition, BashTool(jobs: jobs).definition,
            JobActionTool(jobs: jobs).definition, NarrowSandboxTool(jobs: jobs).definition,
            TasksTool(board: TaskBoard()).definition, IdeasTool(board: IdeaBoard(), tasks: TaskBoard()).definition,
            FetchTool().definition, SessionSearchTool(currentSession: { nil }).definition,
            SkillTool(catalog: SkillCatalog(), knownSources: []).definition, QuestionTool().definition,
            CodemodeTool.definition(python: true), AgentTool().definition, MCPSearchTool(catalog: catalog).definition,
            MCPCallTool(catalog: catalog).definition, MCPResourceTool(shelf: MCPResourceShelf()).definition
        ]
    }

    /// Declared, and offered to no model: `write` and `job` run them.
    private static let inner: Set<String> = ["edit", "wait", "job_stop"]

    /// The arguments of `schema`, at any depth, that say nothing of themselves and that the object holding them does not name in
    /// what it says, each by its path. A small object may say its fields in one phrase, as `sandbox` does.
    static func silent(in schema: Any?, at path: String = "") -> [String] {
        guard let schema = schema as? [String: Any] else { return [] }
        let holder = (schema["description"] as? String ?? "").split { !$0.isLetter && $0 != "_" }.map(String.init)
        var found: [String] = []
        for (name, property) in (schema["properties"] as? [String: Any] ?? [:]).sorted(by: { $0.key < $1.key }) {
            let here = path.isEmpty ? name : path + "." + name
            let said = (property as? [String: Any])?["description"] as? String ?? ""
            if said.isEmpty, !holder.contains(name) { found.append(here) }
            found += silent(in: property, at: here)
        }
        return found + silent(in: schema["items"], at: path + "[]")
    }

    private static func silent(in definition: ToolDefinition) throws -> [String] {
        let schema = try JSONSerialization.jsonObject(with: Data(definition.inputSchema.bytes))
        return silent(in: schema).map { definition.name + ": " + $0 }
    }

    @Test func `every argument of every tool, at any depth, says what it is, or the object holding it does`() throws {
        let silent: [String] = try Self.declared.flatMap { try Self.silent(in: $0) }
        #expect(silent.isEmpty, "say what each is, with described(_:) or a field's description: \(silent)")
    }

    @Test func `the check finds an argument nothing says anything of, at the top, in an object and in a list`() throws {
        let quiet = ToolDefinition(
            name: "quiet",
            description: "Quiet.",
            fields: [
                .init("said", .string(), "It says."),
                .init("top", .string()),
                .init(
                    "object",
                    .object([.init("inside", .boolean), .init("named", .boolean)]),
                    "It says, of named too."
                ),
                .init(
                    "list",
                    .array(.object([.init("each", .integer(), "It says."), .init("other", .string())])),
                    "It says."
                )
            ]
        )
        #expect(try Self.silent(in: quiet) == ["quiet: list[].other", "quiet: object.inside", "quiet: top"])
    }

    /// `codemode` shows a script each tool's first line, cut at 200 characters (`CodemodeTool.brief`).
    @Test func `a tool's first line says what it is for, whole in what a script's list of tools shows`() {
        for definition in Self.declared {
            let first = definition.description.prefix { !$0.isNewline }
            #expect(first.count <= 200 && first.hasSuffix("."), "\(definition.name): \(first.count) characters")
            #expect(CodemodeTool.brief(definition.description) == first)
        }
    }

    @Test func `no tool is declared that this suite does not read`() throws {
        let sources = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources/AskTools")
        var named: Set<String> = []
        for file in try FileManager.default.contentsOfDirectory(at: sources, includingPropertiesForKeys: nil)
        where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for declaration in text.components(separatedBy: "ToolDefinition(").dropFirst() {
                let head = declaration.prefix(80)
                guard let start = head.range(of: "name: \"") else { continue }
                named.insert(String(head[start.upperBound...].prefix { $0 != "\"" }))
            }
        }
        let read = Set(Self.declared.map(\.name))
        #expect(named.count >= 16, "the scan found the declarations: \(named.sorted())")
        let unread = named.subtracting(read).subtracting(Self.inner).sorted()
        #expect(unread.isEmpty, "add each to `declared`, or to `inner` when no model is offered it: \(unread)")
    }
}
