internal import Foundation
internal import Testing

@testable import AskCore

/// Keeps provider knowledge in the places that own it, so a second provider is a new directory and not a
/// change to the loop.
///
/// Provider-specific code lives in `Sources/AskAI/Anthropic` and `Sources/AskAI/Claude` (the wire protocol
/// and the subscription sign-in) and is bound together in `Sources/ask`, the composition root. Everything
/// else is the vocabulary those adapters translate into, and a provider's name appearing there means the
/// seam has started to bend around one provider. The roadmap's own rule for the second provider was "map
/// onto the seam, never widen it"; this is the part of that rule a scan can hold.
@Suite("Provider names stay inside provider code")
struct ProviderNeutralityTests {
    /// Directories that must not name a provider in code, by path fragment.
    private static let neutral = [
        "/Sources/AskAgentCore/", "/Sources/AskTools/", "/Sources/AskTUI/", "/Sources/AskCore/",
        "/Sources/AskAI/Model/", "/Sources/AskAI/Transport/", "/Sources/AskAI/Support/"
    ]

    private static let providers = [
        "Anthropic", "anthropic", "Claude", "claude", "OpenAI", "openai", "Spettro", "spettro"
    ]

    @Test(arguments: ProviderNeutralityTests.providers)
    func `a provider's name does not appear in provider-neutral code`(provider: String) throws {
        let files = SourceStandards.sources.filter { file in Self.neutral.contains { file.path.contains($0) } }
        #expect(!files.isEmpty, "The neutral directories moved; update this list, do not let the scan pass on nothing.")
        let offenders = try SourceStandards.occurrences(of: provider, in: files)
        #expect(
            offenders.isEmpty,
            """
            `\(provider)` belongs in Sources/AskAI/Anthropic, Sources/AskAI/Claude or the composition root. \
            Neutral code speaks in ModelRequest, ModelEvent and ModelProvider.
            Found: \(offenders.joined(separator: "\n  "))
            """
        )
    }
}
