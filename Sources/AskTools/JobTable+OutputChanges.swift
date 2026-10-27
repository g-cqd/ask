extension JobTable {
    /// Reading a snapshot never advances wait's unread output cursor.
    public func snapshot(of id: String) -> JobSnapshot? {
        job(id)?.snapshot(output: outputTail(of: id, maximumBytes: 64 << 10))
    }

    /// Output notifications for `id`, or an empty stream for an unknown job. Reading does not consume tool output.
    public func outputChanges(of id: String) -> AsyncStream<Void> {
        job(id)?.outputChanges() ?? AsyncStream { $0.finish() }
    }
}
