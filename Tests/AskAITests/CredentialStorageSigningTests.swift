import Testing

@testable import AskAI

/// Only a build signed as ask keeps secrets in the Keychain on its own (roadmap 0110). The test host is signed by Apple, a stable
/// identity that is not ask's: counted as stable, every test that made a credential file moved its secrets into the person's login
/// Keychain, and on 2026-11-13 a fixture moved the person's own, which their ad-hoc ask then had to ask for at every read.
@Suite("Only a build signed as ask counts as stably signed")
struct CredentialStorageSigningTests {
    @Test func `a stable identity counts only with ask's identifier`() {
        #expect(CredentialStorage.countsAsStable(adhoc: false, hasCertificates: true, identifier: "ask"))
        #expect(
            !CredentialStorage.countsAsStable(
                adhoc: false,
                hasCertificates: true,
                identifier: "com.apple.dt.swiftpm-testing-helper"
            )
        )
        #expect(!CredentialStorage.countsAsStable(adhoc: false, hasCertificates: true, identifier: nil))
        #expect(!CredentialStorage.countsAsStable(adhoc: true, hasCertificates: true, identifier: "ask"))
        #expect(!CredentialStorage.countsAsStable(adhoc: false, hasCertificates: false, identifier: "ask"))
    }

    @Test func `the test host is not ask, so no test puts a secret in the Keychain by default`() {
        #expect(!CredentialStorage.runningBuildIsStablySigned)
        #expect(!CredentialStorage.auto.usesKeychain(stablySigned: CredentialStorage.runningBuildIsStablySigned))
    }
}
