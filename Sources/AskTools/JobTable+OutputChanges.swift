extension JobTable {
    /// Output notifications for `id`, or an empty stream for an unknown job. Reading does not consume tool output.
    public func outputChanges(of id: String) -> AsyncStream<Void> {
        job(id)?.outputChanges() ?? AsyncStream { $0.finish() }
    }
}
