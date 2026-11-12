internal import Foundation

/// Cloud Code's fixed address and the identity ask presents to it.
///
/// The address is the one the shipped `agy` calls. The identity is ask's own: the live probes (ADR-0080) showed onboarding, the model
/// list and streaming all answer to it, so no first-party client name is claimed. The version is 0 because ask has none.
///
/// The `antigravity/cli/<version>` prefix is the one thing the server reads: it grows the model list with the version it names
/// (probed 2026-11-12: 0.0.1 and 1.0.0 give 20 entries, 1.2.0 gives 23, 1.3.0 and every later one 27). ``AgyVersions`` keeps it current.
enum AgyCloud {
    static let baseURL = URL.constant("https://daily-cloudcode-pa.googleapis.com")

    /// The `User-Agent`, and the envelope's `userAgent`, for a request naming `version` as the `agy` it follows.
    static func userAgent(version: String) -> String {
        "antigravity/cli/\(version) ask/0 (Antigravity subscription connector)"
    }

    /// The platform name Cloud Code's client metadata uses for this machine.
    static var platform: String {
        #if arch(arm64)
            "DARWIN_ARM64"
        #else
            "DARWIN_AMD64"
        #endif
    }
}
