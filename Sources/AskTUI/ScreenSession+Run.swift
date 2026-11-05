internal import TerminalKitIO
internal import TerminalKitInput
internal import TerminalKitRender

/// The screen's timers and frames.
extension ScreenSession {
    /// Runs the screen until it closes, on a thread of its own (``ScreenExecutor``, note n18): keys, the wheel and every update are
    /// applied there, ahead of whatever else the machine is doing.
    func run(resizes: AsyncStream<Void>, appearances: AsyncStream<Void>) async throws -> ScreenExit {
        let executor = ScreenExecutor()
        defer { executor.stop() }
        return try await withTaskExecutorPreference(executor) {
            try await loop(on: executor, resizes: resizes, appearances: appearances)
        }
    }

    private func loop(on executor: ScreenExecutor, resizes: AsyncStream<Void>, appearances: AsyncStream<Void>)
        async throws
        -> ScreenExit
    {
        let input = input
        let sink = sink
        let forwarding = Task(executorPreference: executor) {
            for await event in input.events { sink.yield(.input(event)) }
            sink.yield(.inputEnded)
        }
        let resizing = Task(executorPreference: executor) {
            for await _ in resizes { sink.yield(.resize) }
        }
        let watching = conversation.background { sink.yield(.update($0)) }
        input.start()
        let recolouring = SystemAppearance.askAgain(after: appearances) { sink.yield(.askColours) }
        defer { recolouring.cancel() }
        colours?.ask()
        defer {
            forwarding.cancel()
            resizing.cancel()
            watching?.cancel()
            input.stop()
        }
        defer {
            autoscroll.stop()
            progress.stop()
            runnerOutput.stop()
            for task in jobOutput.values { task.cancel() }
        }
        render(full: true)
        for await event in events {
            if let taken = colours?.take(event) {
                if case .page(let page) = taken { controller.state.adopt(page) }
                render(full: true)
                continue
            }
            guard await handle(event) else { return exit }
        }
        return exit
    }

    func syncAutoscroll() {
        let sink = sink
        autoscroll.update(wanted: controller.isAutoscrolling) { sink.yield(.tick) }
    }

    /// Hands the render thread the screen as it is now. It draws the newest state it finds, so a burst of events is
    /// one frame, and this never waits for one.
    func render(full: Bool = false) {
        if full { renderer.redraw() }
        renderer.submit(controller.state)
    }

    /// The progress timer as the screen now wants it: off with nothing live, faster while a running header shimmers.
    func syncProgress() {
        progress.update(wanted: controller.hasLiveProgress, shimmering: controller.isShimmering) { [sink] in
            sink.yield(.progressTick(advancesFrames: $0))
        }
    }
}
