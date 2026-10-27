internal import Foundation

/// Cloud Code's fixed address and the identity ask presents to it.
///
/// The address is the one the shipped `agy` calls. The identity is ask's own: the live probes (ADR-0080) showed onboarding, the model
/// list and streaming all answer to it, so no first-party client name is claimed. The version is 0 because ask has none.
enum AgyCloud {
    static let baseURL = URL(string: "https://daily-cloudcode-pa.googleapis.com")!
    static let userAgent = "antigravity/cli/1.4.0 ask/0 (Antigravity subscription connector)"

    /// The platform name Cloud Code's client metadata uses for this machine.
    static var platform: String {
        #if arch(arm64)
            "DARWIN_ARM64"
        #else
            "DARWIN_AMD64"
        #endif
    }
}
