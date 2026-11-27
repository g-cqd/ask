internal import Darwin
internal import Foundation

/// A pseudo-terminal pair of a given size (ADR-0170): the replica is a viewer's terminal, as a terminal window's would be, and the
/// primary carries its bytes to and from the viewer.
package struct PseudoTerminal: Sendable {
    package let primary: Int32
    package let replica: Int32

    /// A new pair, `columns` by `rows`, neither inherited by a child process.
    package init(columns: UInt16, rows: UInt16) throws {
        var primary: Int32 = -1
        var replica: Int32 = -1
        var size = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        guard unsafe openpty(&primary, &replica, nil, nil, &size) == 0 else { throw POSIXError(.ENOTTY) }
        for descriptor in [primary, replica] { _ = fcntl(descriptor, F_SETFD, FD_CLOEXEC) }
        self.primary = primary
        self.replica = replica
    }

    /// Types `bytes` into the terminal, as its keyboard would.
    package func write(_ bytes: [UInt8]) { DescriptorReader.writeAll(bytes, to: primary) }

    /// What was written to the terminal, read from the primary until `done` says so or `seconds` pass: how a test or a probe watches
    /// what a screen drew, without waiting longer than it must.
    package func read(within seconds: Double = 15, until done: (String) -> Bool) -> String {
        var seen: [UInt8] = []
        let deadline = Date().addingTimeInterval(seconds)
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while Date() < deadline, !done(String(decoding: seen, as: UTF8.self)) {
            var descriptor = pollfd(fd: primary, events: Int16(POLLIN), revents: 0)
            guard poll(&descriptor, 1, 50) > 0 else { continue }
            let count = buffer.withUnsafeMutableBytes { unsafe Darwin.read(primary, $0.baseAddress, $0.count) }
            guard count > 0 else { break }
            seen += buffer[..<count]
        }
        return String(decoding: seen, as: UTF8.self)
    }

    /// Sets the terminal's size, as a window resized would.
    package func resize(columns: UInt16, rows: UInt16) {
        var size = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        _ = unsafe ioctl(primary, UInt(TIOCSWINSZ), &size)
    }
}
