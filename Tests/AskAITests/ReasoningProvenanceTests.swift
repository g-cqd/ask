import Testing

@testable import AskAI

/// A thinking block's signature belongs to the protocol that issued it, and travels only back to that protocol.
///
/// Anthropic refuses a signature it did not issue, and another protocol's reasoning item means nothing to it; ask
/// marks what a non-Anthropic protocol issues so every encoder can tell its own from the rest (ADR-0033).
@Suite("Reasoning provenance marks a signature with the protocol that issued it")
struct ReasoningProvenanceTests {
    @Test func `a marked signature gives its payload back to its own scheme only`() {
        let signature = ReasoningProvenance.mark(
            scheme: "responses", payload: #"{"id":"rs_1","encrypted_content":"abc"}"#)
        #expect(
            ReasoningProvenance.payload(of: signature, scheme: "responses")
                == #"{"id":"rs_1","encrypted_content":"abc"}"#)
        #expect(ReasoningProvenance.payload(of: signature, scheme: "other") == nil)
    }

    @Test func `a marked signature is foreign; Anthropic's, empty, and look-alikes are not`() {
        #expect(ReasoningProvenance.isForeign(ReasoningProvenance.mark(scheme: "responses", payload: "x")))
        #expect(!ReasoningProvenance.isForeign(""))
        #expect(!ReasoningProvenance.isForeign("EqQBCgIYAhIM1gbcDa9GJwZA2b3hGgxBdjrkzLoky3dl1pkiMDdYWPAcrNnQ"))
        #expect(!ReasoningProvenance.isForeign("responses:x"))
    }

    @Test func `a signature that is not marked yields no payload for any scheme`() {
        #expect(ReasoningProvenance.payload(of: "sig==", scheme: "responses") == nil)
        #expect(ReasoningProvenance.payload(of: "", scheme: "responses") == nil)
    }

    @Test func `the scheme and payload are split at the first separator, so a payload may hold colons`() {
        let signature = ReasoningProvenance.mark(scheme: "responses", payload: "a:b:c")
        #expect(ReasoningProvenance.payload(of: signature, scheme: "responses") == "a:b:c")
    }
}
