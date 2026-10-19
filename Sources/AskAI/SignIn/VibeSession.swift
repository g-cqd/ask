public import Foundation

/// What Mistral Vibe's sign-in keeps between its start and its exchange: the process to poll and exchange, and the
/// verifier that proves the exchange comes from whoever started it.
public struct VibeSession: Sendable, Equatable {
    let processID: String
    let pollURL: URL
    let verifier: String
}
