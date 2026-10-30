import Testing

@testable import AskAgentCore

/// What a workspace-only run may still write (owner, 2026-10-29: the default write scope is the workspace): the caches builds write,
/// and nothing that runs later.
@Suite("Developer caches stay writable when writing is kept to the workspace")
struct DeveloperWritesTests {
    @Test func `build caches are writable, toolchains and general caches are not`() {
        let writes = SandboxPolicy.developerWrites(home: "/h")
        for path in [
            "/h/Library/Caches", "/h/Library/Developer/Xcode/DerivedData", "/h/Library/org.swift.swiftpm", "/h/.swiftpm"
        ] {
            #expect(writes.contains(path), "\(path)")
        }
        for path in ["/h/Library/Developer/Toolchains", "/h/.swiftly", "/h/.cache", "/h/Library"] {
            #expect(!writes.contains(path), "\(path)")
        }
    }
}
