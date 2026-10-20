/// A tool call's `sandbox` argument that is not a request.
public struct SandboxRequestError: Error, Sendable, Equatable, CustomStringConvertible {
    public let description: String

    init(_ description: String) { self.description = description }
}
