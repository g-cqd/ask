import Testing

@testable import AskAgentCore

@Suite("The environment section names what commands may and may not inherit, and a project can only withhold more")
struct EnvironmentSectionTests {
    private func parse(_ text: String, project: Bool = false) throws(ConfigurationError) -> ConfigurationFile {
        try ConfigurationFile.parse(Array(text.utf8), path: "c.json", isProject: project)
    }

    @Test func `a file reads both lists, sorted and without repeats, and reports only names`() throws {
        let file = try parse("{environment:{pass:['SSH_AUTH_SOCK','SSH_AUTH_SOCK'],withhold:['MY_TOKEN','AWS_*']}}")
        #expect(file.environment == EnvironmentSection(pass: ["SSH_AUTH_SOCK"], withhold: ["AWS_*", "MY_TOKEN"]))
        #expect(file.environment?.pass == ["SSH_AUTH_SOCK"] && file.environment?.withhold == ["AWS_*", "MY_TOKEN"])
        #expect(file.environment?.description == "pass SSH_AUTH_SOCK; withhold AWS_*, MY_TOKEN")
        #expect(EnvironmentSection().description == "none" && EnvironmentSection().isEmpty)
        #expect(!EnvironmentSection(pass: ["X"]).isEmpty)
        #expect(!EnvironmentSection(withhold: ["X"]).isEmpty)
    }

    @Test func `an unknown key and a wrong type are refused by name`() {
        #expect(throws: ConfigurationError.self) { try parse("{environment:{nope:[]}}") }
        #expect(throws: ConfigurationError.self) { try parse("{environment:{pass:'X'}}") }
        #expect(throws: ConfigurationError.self) { try parse("{environment:{withhold:[1]}}") }
    }

    @Test func `a name must be a variable name, and a prefix only in withhold`() {
        for bad in ["", "1ABC", "A B", "A=B", "A-B", "*", "A*B", String(repeating: "A", count: 129)] {
            #expect(throws: ConfigurationError.self, "\(bad.debugDescription)") {
                try parse("{environment:{withhold:['\(bad)']}}")
            }
        }
        #expect(throws: ConfigurationError.self) { try parse("{environment:{pass:['AWS_*']}}") }
        do { _ = try parse("{environment:{withhold:['A B']}}") } catch {
            guard case .outOfRange("c.json", "environment.withhold", let reason) = error else {
                Issue.record("expected the withhold key to be named, got \(error)")
                return
            }
            #expect(reason.contains("\"A B\"") && reason.contains("not a variable name"))
        }
    }

    @Test func `there is a limit to how many names a list may hold`() throws {
        let many = (0 ..< 257).map { "'V\($0)'" }.joined(separator: ",")
        #expect(throws: ConfigurationError.self) { try parse("{environment:{withhold:[\(many)]}}") }
        let enough = (0 ..< 256).map { "'V\($0)'" }.joined(separator: ",")
        #expect(try parse("{environment:{withhold:[\(enough)]}}").environment?.withhold.count == 256)
    }

    @Test func `a project's file may withhold more and may not pass anything`() throws {
        #expect(
            try parse("{environment:{withhold:['X','AWS_*']}}", project: true).environment?.withhold == ["AWS_*", "X"])
        #expect(throws: ConfigurationError.self) { try parse("{environment:{pass:['X']}}", project: true) }
        #expect(
            try parse("{environment:{pass:[],withhold:['X']}}", project: true).environment?.withhold == ["X"],
            "an empty pass passes nothing")
    }

    @Test func `layers add their names to each other's`() {
        let user = ConfigurationFile(environment: EnvironmentSection(pass: ["A"], withhold: ["X"]))
        let project = ConfigurationFile(environment: EnvironmentSection(withhold: ["Y"]))
        let combined = Configuration.defaults.applying(user, from: .file("u")).applying(project, from: .file("p"))
        #expect(combined.environment.value == EnvironmentSection(pass: ["A"], withhold: ["X", "Y"]))
        #expect(combined.environment.source == .file("p"))
        #expect(combined.changes(from: .defaults).contains { $0.hasPrefix("environment:") })
    }

    @Test func `environment is a known key`() {
        #expect(
            ConfigurationFile.keys.contains("environment")
                && ConfigurationFile(environment: EnvironmentSection()).sets("environment"))
        #expect(!ConfigurationFile().sets("environment"))
    }
}
