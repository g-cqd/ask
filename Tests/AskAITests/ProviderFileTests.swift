internal import Foundation
internal import Testing

@testable import AskAI

/// `ask login custom` adds an endpoint to providers.json without losing what the person wrote there, and never writes a key into it.
@Suite("A custom endpoint is added to providers.json, keeping the rest and never holding a key")
struct ProviderFileTests {
    private let path = FileManager.default.temporaryDirectory
        .appending(path: "ask-providers-\(UUID().uuidString)/ask/providers.json").path

    @Test func `the file is made, with the endpoint and its protocol`() throws {
        try ProviderFile.addEndpoint(name: "My-LLM", baseURL: "http://localhost:8181/v1/", at: path)
        let settings = try ProviderSettings.load(from: path)
        let resolved = try settings.resolve(provider: "my-llm", model: "m", environment: [:])
        guard case .openAICompatible(let name, let url, let key, _) = resolved.provider else {
            Issue.record("not an OpenAI-compatible provider")
            return
        }
        #expect(name == "my-llm" && url.absoluteString == "http://localhost:8181/v1" && key == nil)
    }

    @Test func `what the file already holds is kept`() throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data(
            #"{"default":"local","providers":{"local":{"api":"openai-completions","baseUrl":"http://127.0.0.1:1/v1","models":[{"id":"x"}]}}}"#
                .utf8
        )
        .write(to: URL(fileURLWithPath: path))
        try ProviderFile.addEndpoint(name: "other", baseURL: "https://example.com/v1", responses: true, at: path)
        let settings = try ProviderSettings.load(from: path)
        #expect(settings.configuredNames == ["local", "other"])
        #expect(settings.namesDefault)
        #expect(try settings.resolve(provider: "local", model: nil, environment: [:]).model == "x")
    }

    @Test func `a stored key is the key of an endpoint that writes none`() throws {
        try ProviderFile.addEndpoint(name: "my-llm", baseURL: "https://example.com/v1", at: path)
        let resolved = try ProviderSettings.load(from: path)
            .resolve(provider: "my-llm", model: "m", environment: [:], storedKeys: { ["my-llm": "stored-key"] })
        guard case .openAICompatible(_, _, let key, _) = resolved.provider else {
            Issue.record("not an OpenAI-compatible provider")
            return
        }
        #expect(key == "stored-key")
    }

    @Test func `the file is owner-only in a private directory, and the old one is replaced whole`() throws {
        try ProviderFile.addEndpoint(name: "a", baseURL: "https://example.com/v1", at: path)
        try ProviderFile.addEndpoint(name: "a", baseURL: "https://example.org/v1", at: path)
        let text = try String(contentsOfFile: path, encoding: .utf8)
        #expect(text.contains("example.org") && !text.contains("example.com"))
        let mode = try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test(arguments: ["", "-x", "A B", "anthropic", "codex", "agy", "apple", "claude", "groq", "openai"])
    func `a name that is not a plain, free name is refused`(name: String) {
        #expect(throws: ProviderFile.Failure.self) {
            try ProviderFile.addEndpoint(name: name, baseURL: "https://example.com/v1", at: path)
        }
        #expect(!FileManager.default.fileExists(atPath: path), "nothing was written")
    }

    @Test func `a plain http address to another machine is refused, since a key would travel in the clear`() {
        #expect(
            throws: ProviderFile.Failure.refusedEndpoint(
                "plain http to another machine would send the credential unencrypted; use https, or http only for localhost"
            )
        ) { try ProviderFile.addEndpoint(name: "remote", baseURL: "http://example.com/v1", at: path) }
    }

    @Test func `a file that is not a JSON object is left alone`() throws {
        try FileManager.default.createDirectory(
            atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try Data("[1,2]".utf8).write(to: URL(fileURLWithPath: path))
        #expect(throws: ProviderFile.Failure.self) {
            try ProviderFile.addEndpoint(name: "x", baseURL: "https://example.com/v1", at: path)
        }
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "[1,2]")
    }
}
