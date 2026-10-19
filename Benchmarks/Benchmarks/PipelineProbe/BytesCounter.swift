import Synchronization
import TerminalKitIO

/// A connection that keeps only the size of the last write, so a frame's bytes can be read back.
final class BytesCounter: TerminalConnection {
    private let lastWrite = Atomic<Int>(0)

    var last: Int { lastWrite.load(ordering: .relaxed) }

    func read(into buffer: UnsafeMutableRawBufferPointer) throws(TerminalError) -> Int { 0 }
    func write(_ bytes: [UInt8]) throws(TerminalError) { lastWrite.store(bytes.count, ordering: .relaxed) }
    func writeContiguous(_ bytes: ContiguousArray<UInt8>) throws(TerminalError) {
        lastWrite.store(bytes.count, ordering: .relaxed)
    }
    func enterRawMode() throws(TerminalError) {}
    func restoreMode() throws(TerminalError) {}
    func getSize() throws(TerminalError) -> TerminalSize { TerminalSize(columns: 120, rows: 40) }
}
