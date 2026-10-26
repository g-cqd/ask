internal import Foundation
internal import FoundationModels

/// A tool the framework may call, which does not run: it records the call and ends the response. ask's loop runs the real tool, under
/// its sandbox, and asks the model again with the result.
struct AppleCapturingTool: Tool {
    /// Ends the response once the call is taken; never shown to anyone.
    struct Handoff: Error {}

    let name: String
    let description: String
    let parameters: GenerationSchema
    let capture: AppleCapture

    func call(arguments: GeneratedContent) async throws -> String {
        capture.record(
            .init(id: "apple_" + UUID().uuidString.prefix(8).lowercased(), name: name, arguments: arguments.jsonString))
        throw Handoff()
    }
}
