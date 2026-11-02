/// Told how far a running call has got (roadmap 0067): the call's id, then one short line, such as `25% · reading files`.
public typealias ToolProgressReporter = @Sendable (_ call: String, _ line: String) -> Void
