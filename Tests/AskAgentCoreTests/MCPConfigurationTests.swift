import Testing

@testable import AskAgentCore

@Suite("The mcp section names the servers whose tools the model may use, and only the user can name them")
struct MCPConfigurationTests {
    private func parse(_ text: String, project: Bool = false) throws(ConfigurationError) -> ConfigurationFile {
        try ConfigurationFile.parse(Array(text.utf8), path: "c.json", isProject: project)
    }

    private func refusal(_ text: String) -> String? {
        do {
            _ = try parse(text)
            return nil
        } catch let error {
            if case .outOfRange(_, let key, let reason) = error { return key + ": " + reason }
            return "\(error)"
        }
    }

    @Test func `a command server and a url server are read with everything they say`() throws {
        let file = try parse(
            """
            {mcp:{
              rea:{command:'bunx',args:['rea-agents@6.5.0','mcp'],env:{HOPPER:'/x'},cwd:'/work',tools:['a','b']},
              docs:{url:'https://example.test/mcp',headers:{Authorization:'Bearer ${TOKEN}'},enabled:false}
            }}
            """)
        let servers = try #require(file.mcp?.servers)
        #expect(servers.map(\.name) == ["docs", "rea"], "sorted by name, not by the order a decoder happens to give")
        #expect(
            servers[1]
                == MCPServerSetting(
                    name: "rea", command: "bunx", args: ["rea-agents@6.5.0", "mcp"], env: ["HOPPER": "/x"],
                    cwd: "/work",
                    tools: ["a", "b"]))
        #expect(
            servers[0]
                == MCPServerSetting(
                    name: "docs", url: "https://example.test/mcp", headers: ["Authorization": "Bearer ${TOKEN}"],
                    enabled: false))
    }

    @Test func `a server is on unless it says it is off, and takes every tool unless it lists some`() throws {
        let server = try #require(try parse("{mcp:{a:{command:'x'}}}").mcp?.servers.first)
        #expect(server.enabled && server.tools == nil && server.args.isEmpty && server.env.isEmpty)
    }

    @Test func `the description names servers and how they are reached, and never what they were given`() throws {
        let section = try #require(
            try parse(
                "{mcp:{a:{command:'x',env:{K:'secret'}},b:{url:'https://h.test/m',headers:{Authorization:'secret'}},c:{command:'y',enabled:false}}}"
            )
            .mcp)
        #expect(section.description == "a (command), b (url), c (command, off)")
        #expect(!section.description.contains("secret"))
    }

    @Test func `a server needs exactly one of a command and a url`() {
        #expect(refusal("{mcp:{a:{}}}")?.hasPrefix("mcp.a:") == true)
        #expect(refusal("{mcp:{a:{command:'x',url:'https://h.test'}}}")?.hasPrefix("mcp.a:") == true)
    }

    @Test func `a url must be http or https, and a command must not be empty`() {
        #expect(refusal("{mcp:{a:{url:'ftp://h.test'}}}")?.hasPrefix("mcp.a.url:") == true)
        #expect(refusal("{mcp:{a:{url:'nonsense'}}}")?.hasPrefix("mcp.a.url:") == true)
        #expect(refusal("{mcp:{a:{command:''}}}")?.hasPrefix("mcp.a.command:") == true)
    }

    @Test func `a name is letters, digits, dashes and single underscores, because it becomes part of a tool's name`() {
        for bad in ["'a b'", "'a.b'", "'a__b'", "'-a'", "''", "'" + String(repeating: "a", count: 33) + "'"] {
            #expect(refusal("{mcp:{\(bad):{command:'x'}}}") != nil, "\(bad)")
        }
        for good in ["a", "rea-2", "My_server", "x1"] {
            #expect(refusal("{mcp:{'\(good)':{command:'x'}}}") == nil, "\(good)")
        }
    }

    @Test func `keys that do not belong to the kind of server are refused instead of ignored`() {
        #expect(refusal("{mcp:{a:{url:'https://h.test',args:['x']}}}")?.hasPrefix("mcp.a.args:") == true)
        #expect(refusal("{mcp:{a:{command:'x',headers:{A:'b'}}}}")?.hasPrefix("mcp.a.headers:") == true)
        #expect(throws: ConfigurationError.self) { try parse("{mcp:{a:{command:'x',nope:1}}}") }
        #expect(throws: ConfigurationError.self) { try parse("{mcp:{a:{command:'x',args:'y'}}}") }
        #expect(throws: ConfigurationError.self) { try parse("{mcp:{a:{command:'x',env:{K:1}}}}") }
    }

    @Test func `an empty tool list or an empty tool name is refused`() {
        #expect(refusal("{mcp:{a:{command:'x',tools:[]}}}")?.hasPrefix("mcp.a.tools:") == true)
        #expect(refusal("{mcp:{a:{command:'x',tools:['']}}}")?.hasPrefix("mcp.a.tools:") == true)
    }

    @Test func `a project's file may name a server, because it is read only once it is trusted`() throws {
        let file = try parse("{mcp:{a:{command:'x',args:['y']},b:{url:'https://h.test/m'}}}", project: true)
        #expect(file.mcp?.servers.map(\.name) == ["a", "b"])
    }

    @Test func `a project's file may not read ask's environment into a server, where a repository could carry it away`()
    {
        for text in [
            "{mcp:{a:{command:'x',env:{K:'${ANTHROPIC_API_KEY}'}}}}",
            "{mcp:{a:{url:'https://h.test',headers:{Authorization:'Bearer ${TOKEN}'}}}}",
            "{mcp:{a:{command:'x',env:{K:'prefix ${X} suffix'}}}}"
        ] {
            #expect(throws: ConfigurationError.self) { try parse(text, project: true) }
            #expect(throws: Never.self) { try parse(text) }
        }
    }

    @Test func `a project's literal values are fine, and so is a dollar sign that names nothing`() throws {
        _ = try parse("{mcp:{a:{command:'x',env:{K:'plain',P:'costs $5',Q:'${unterminated'}}}}", project: true)
    }

    @Test
    func
        `what trusting a project would start is told in a line a server, with the command or the address and nothing it was given`()
        throws
    {
        let file = try parse(
            "{mcp:{a:{command:'bunx',args:['rea-agents@6.5.0','mcp'],env:{K:'secret'}},b:{url:'https://h.test/m?token=x',headers:{A:'secret'}},c:{command:'y',enabled:false}}}",
            project: true)
        let lines = try #require(file.mcp).consent
        #expect(lines == ["a: runs bunx rea-agents@6.5.0 mcp", "b: connects to https://h.test/m", "c: runs y (off)"])
        #expect(!lines.joined().contains("secret") && !lines.joined().contains("token"))
    }

    @Test func `a section with no servers has nothing to consent to`() {
        #expect(MCPSection().consent.isEmpty)
    }

    @Test func `a later layer replaces a server of the same name whole, and adds the others`() {
        let first = ConfigurationFile(
            mcp: MCPSection(servers: [
                MCPServerSetting(name: "a", command: "one", args: ["x"]), MCPServerSetting(name: "b", command: "b")
            ]))
        let second = ConfigurationFile(mcp: MCPSection(servers: [MCPServerSetting(name: "a", command: "two")]))
        let combined = Configuration.defaults.applying(first, from: .file("u")).applying(second, from: .file("v"))
        #expect(
            combined.mcp.value.servers == [
                MCPServerSetting(name: "a", command: "two"), MCPServerSetting(name: "b", command: "b")
            ])
        #expect(combined.changes(from: .defaults).contains { $0.hasPrefix("mcp:") })
    }

    @Test func `mcp is a known key`() {
        #expect(ConfigurationFile.keys.contains("mcp") && ConfigurationFile(mcp: MCPSection()).sets("mcp"))
    }
}
