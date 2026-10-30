internal import AskAI
internal import FoundationModels
internal import Testing

@testable import AskApple

/// The framework's failures as the failures the loop already answers: a window that is too small is compacted, and nothing else is retried
/// blindly.
@Suite("The framework's failures become the failures the loop knows")
struct AppleFailureTests {
    // The macOS 27 SDK's error type (Foundation Models 2), as in AppleFailure: these compile only against that SDK.
    #if canImport(FoundationModels, _version: 2)
        @Test func `a window overflow is the loop's cue to compact, and names the window`() throws {
            guard #available(macOS 27.0, *) else { return }
            let failure = AppleFailure.mapped(
                LanguageModelError.contextSizeExceeded(.init(contextSize: 4096, tokenCount: 5000, debugDescription: ""))
            )
            let mapped = try #require(failure as? ProviderFailure)
            #expect(mapped.kind == .contextOverflow && mapped.contextWindow == AppleModel.contextWindow)
        }

        @Test func `a safety refusal is an invalid request, said in a sentence`() throws {
            guard #available(macOS 27.0, *) else { return }
            let failure = AppleFailure.mapped(LanguageModelError.guardrailViolation(.init(debugDescription: "x")))
            let mapped = try #require(failure as? ProviderFailure)
            #expect(mapped.kind == .invalidRequest && mapped.message == "The on-device model declined this request.")
        }
    #endif

    @Test func `an error that is not the framework's is passed on as it is`() {
        struct Other: Error {}
        #expect(AppleFailure.mapped(Other()) is Other)
    }
}
