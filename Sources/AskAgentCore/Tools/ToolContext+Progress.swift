extension ToolContext {
    /// Whether anyone is told of this call's progress; a tool that must ask for progress (a server's) asks only then.
    public var reportsProgress: Bool { progress != nil && callID != nil }

    /// Tells the run how far this call has got, as one short line; nothing outside a call or with no one to tell.
    public func reportProgress(_ line: String) {
        guard let progress, let callID else { return }
        progress(callID, line)
    }
}
