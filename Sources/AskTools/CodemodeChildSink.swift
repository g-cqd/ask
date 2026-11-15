internal import AemiJSONRPC

/// What a keeper's connection writes its messages through: the child's input, a message a line. The connection ends each
/// with a line end, and the child's transport adds its own.
struct CodemodeChildSink: JSONRPCSink {
    let child: CodemodeChild

    init(_ child: CodemodeChild) { self.child = child }

    func write(_ bytes: [UInt8]) async throws {
        try await child.send(bytes.last == 0x0A ? Array(bytes.dropLast()) : bytes)
    }
}
