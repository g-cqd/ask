/// One measured case: how many calls, how long they took, and the floor it is compared with.
struct Measurement {
    var name: String
    var calls: Int
    var elapsed: Duration
    var floor: Duration?

    /// Nanoseconds a call.
    var perCall: Double { Self.nanoseconds(elapsed) / Double(calls) }

    var line: String {
        var text =
            name.padding(toLength: 46, withPad: " ", startingAt: 0) + Self.time(perCall).leftPadded(11)
            + String(Int(1e9 / perCall)).leftPadded(10) + " calls/s"
        if let floor {
            let floorPerCall = Self.nanoseconds(floor) / Double(calls)
            text +=
                "   floor " + Self.time(floorPerCall).leftPadded(10) + "   x" + String(format: perCall / floorPerCall)
        }
        return text
    }

    static func nanoseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1e9 + Double(duration.components.attoseconds) / 1e9
    }

    static func time(_ nanoseconds: Double) -> String {
        nanoseconds >= 1_000_000
            ? String(format: nanoseconds / 1_000_000) + " ms"
            : nanoseconds >= 1000 ? String(format: nanoseconds / 1000) + " µs" : String(format: nanoseconds) + " ns"
    }
}

extension String {
    func leftPadded(_ width: Int) -> String { String(repeating: " ", count: Swift.max(0, width - count)) + self }

    /// Two decimals, without Foundation.
    init(format value: Double) {
        let hundredths = Int((value * 100).rounded())
        let fraction = abs(hundredths % 100)
        self = "\(hundredths / 100).\(fraction < 10 ? "0" : "")\(fraction)"
    }
}

/// Keeps a value alive so the optimizer cannot drop the work that made it.
@inline(never) func keep<T>(_ value: T) { withExtendedLifetime(value) {} }
