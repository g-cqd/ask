internal import Foundation
internal import Testing

@testable import AskAI

/// What a person is told when Antigravity access fails: what happened, and what to do about it.
struct AgyAccessErrorTests {
    @Test func `a signed-out account is told the command that signs in`() {
        #expect(AgyAccessError.signedOut.description.contains("ask login agy"))
    }

    @Test
    func `a grant Google no longer honours is told to sign in again, and a changed sign-in to run the command again`() {
        let grant = AgyAccessError.refreshFailed(.tokenEndpoint(status: 400, code: "invalid_grant")).description
        #expect(grant.contains("ask login agy") && grant.contains("could not be refreshed"))
        #expect(AgyAccessError.changedDuringRefresh.description.contains("run the command again"))
    }

    @Test func `the reason a secret or a network failed is repeated, and says which it was`() {
        let secret = AgyAccessError.secretUnavailable("agy is not installed").description
        #expect(secret.contains("agy is not installed") && secret.contains("secret"))
        let network = AgyAccessError.unreachable("offline").description
        #expect(network.contains("offline") && network.contains("could not be reached"))
    }

    @Test func `an unreadable credential file and an account with no project are described by their own words`() {
        let damaged = AgyAccessError.storage(.damaged(path: "/x/credentials.json")).description
        #expect(damaged.contains("/x/credentials.json") && damaged.contains("Antigravity"))
        #expect(
            AgyAccessError.onboarding(.noProject(reasons: ["UNSUPPORTED_LOCATION"])).description
                .contains("UNSUPPORTED_LOCATION"))
    }
}
