internal import Testing

@testable import AskAgentCore

struct SessionDestinationTests {
    private let original = SessionDestination(
        connectionID: "connection-1", authorizationID: "grant-1", name: "work", model: "one")

    @Test func `legacy history continues on an unnamed provider, as it always could`() throws {
        let unnamed = SessionDestination(
            connectionID: "provider:local", authorizationID: nil, name: "local", model: "m")
        try unnamed.check(replacing: nil, hasHistory: true, explicitlySelected: false)
        #expect(!unnamed.isNamed)
    }

    @Test func `legacy history cannot silently go to a named connection`() {
        #expect(original.isNamed)
        #expect(throws: SessionDestinationError.unbound) {
            try original.check(replacing: nil, hasHistory: true, explicitlySelected: false)
        }
    }

    @Test func `another connection or authorization cannot silently inherit history`() {
        for candidate in [
            SessionDestination(connectionID: "connection-2", authorizationID: "grant-1", name: "other", model: "one"),
            SessionDestination(connectionID: "connection-1", authorizationID: "grant-2", name: "work", model: "one")
        ] {
            #expect(throws: SessionDestinationError.changed) {
                try candidate.check(replacing: original, hasHistory: true, explicitlySelected: false)
            }
        }
    }

    @Test func `a rename or model selection does not change which account receives history`() throws {
        let renamed = SessionDestination(
            connectionID: "connection-1", authorizationID: "grant-1", name: "employer", model: "two")
        try renamed.check(replacing: original, hasHistory: true, explicitlySelected: false)
    }

    @Test func `a fresh session and an explicit override need no inherited consent`() throws {
        try original.check(replacing: nil, hasHistory: false, explicitlySelected: false)
        try original.check(replacing: nil, hasHistory: true, explicitlySelected: true)
        let other = SessionDestination(
            connectionID: "connection-2", authorizationID: "grant-2", name: "other", model: "two")
        try other.check(replacing: original, hasHistory: true, explicitlySelected: true)
    }
}
