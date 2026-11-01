/// No idle work: animation exists only while a tool or thinking block is live.
///
/// Spinners and clocks step every 200 ms. While a running header shimmers (roadmap 0187), the timer ticks every 60 ms instead, so the
/// bright stretch glides rather than jumps; only every 200 ms does a tick advance the spinners, so they keep their pace.
struct BlockProgressTimer {
    static let frameInterval = Duration.milliseconds(200)
    static let shimmerInterval = Duration.milliseconds(60)

    private var task: Task<Void, Never>?
    private var interval = frameInterval

    /// - Parameters:
    ///   - wanted: whether anything is live.
    ///   - shimmering: whether a running header shimmers, which wants the faster tick.
    ///   - post: called each tick, told whether the tick advances the spinners' frames.
    mutating func update(wanted: Bool, shimmering: Bool = false, post: @escaping @Sendable (Bool) -> Void) {
        guard wanted else {
            stop()
            return
        }
        let wantedInterval = shimmering ? Self.shimmerInterval : Self.frameInterval
        guard task == nil || wantedInterval != interval else { return }
        stop()
        interval = wantedInterval
        let tick = wantedInterval
        task = Task {
            var sinceFrame = Duration.zero
            while !Task.isCancelled {
                do { try await Task.sleep(for: tick) } catch { return }
                let advances = Self.advances(&sinceFrame, after: tick)
                if !Task.isCancelled { post(advances) }
            }
        }
    }

    /// Whether a tick of `tick` steps the spinners, `sinceFrame` being the time since they last did: the remainder is kept, so frames
    /// come every 200 ms on average whatever the tick.
    static func advances(_ sinceFrame: inout Duration, after tick: Duration) -> Bool {
        sinceFrame += tick
        guard sinceFrame >= frameInterval else { return false }
        sinceFrame -= frameInterval
        return true
    }

    mutating func stop() {
        task?.cancel()
        task = nil
    }
}
