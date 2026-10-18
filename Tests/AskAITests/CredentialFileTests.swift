import Foundation
import Testing

@testable import AskAI

/// Credentials on disk: owner-only, written atomically, and refused when anyone else could read them.
@Suite("Credentials are stored owner-only and refused when exposed")
struct CredentialFileTests {
    private let directory: URL
    private let file: CredentialFile
    private let credentials = ClaudeCredentials(
        accessToken: "sk-ant-oat-A", refreshToken: "sk-ant-ort-R", expiresAt: 1_000, refreshExpiresAt: nil,
        accountEmail: "a@b.c", organizationName: nil, scopes: "user:inference")

    init() {
        // Several missing levels, as a fresh XDG_CONFIG_HOME would be.
        directory = FileManager.default.temporaryDirectory.appending(path: "ask-cred-\(UUID().uuidString)/a/b/ask")
        file = CredentialFile(url: directory.appending(path: "credentials.json"))
    }

    private func mode(_ url: URL) throws -> Int {
        try (FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) ?? -1
    }

    @Test func `nothing stored loads as nothing`() throws {
        #expect(try file.loadClaude() == nil)
    }

    @Test func `saved credentials load back, owner-only`() throws {
        try file.saveClaude(credentials)
        #expect(try file.loadClaude() == credentials)
        #expect(try mode(file.url) == 0o600)
        #expect(try mode(directory) == 0o700)
    }

    @Test func `saving replaces atomically and leaves no temporary file`() throws {
        try file.saveClaude(credentials)
        var newer = credentials
        newer.accessToken = "sk-ant-oat-B"
        try file.saveClaude(newer)
        #expect(try file.loadClaude() == newer)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["credentials.json"])
    }

    @Test(arguments: [0o640, 0o604, 0o644])
    func `a file others can read is refused, not trusted`(exposed: Int) throws {
        try file.saveClaude(credentials)
        try FileManager.default.setAttributes([.posixPermissions: exposed], ofItemAtPath: file.url.path)
        #expect(throws: CredentialFileError.exposed(path: file.url.path, mode: exposed)) { _ = try file.loadClaude() }
    }

    @Test func `a damaged file is reported, not treated as signed out`() throws {
        try file.saveClaude(credentials)
        try Data("{not json".utf8).write(to: file.url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.url.path)
        #expect(throws: CredentialFileError.damaged(path: file.url.path)) { _ = try file.loadClaude() }
    }

    @Test func `removing signs out`() throws {
        try file.saveClaude(credentials)
        try file.remove()
        #expect(try file.loadClaude() == nil)
        try file.remove()
    }

    @Test func `the standard location follows XDG_CONFIG_HOME, then the home directory`() {
        #expect(
            CredentialFile.standard(environment: ["XDG_CONFIG_HOME": "/x"], home: "/h").url.path
                == "/x/ask/credentials.json")
        #expect(CredentialFile.standard(environment: [:], home: "/h").url.path == "/h/.config/ask/credentials.json")
        #expect(
            CredentialFile.standard(environment: ["XDG_CONFIG_HOME": "relative"], home: "/h").url.path
                == "/h/.config/ask/credentials.json")
    }
}
