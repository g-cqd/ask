internal import TerminalKitIO
internal import TerminalKitInput
internal import TerminalKitRender

/// The screen's mirrors (ADR-0170): attached, drawn with every frame at their own size, their keys applied, and left whole when they
/// go or the screen closes.
extension ScreenSession {
    /// Applies a mirror event; nil when `event` is not one.
    func handleMirror(_ event: ScreenEvent) async -> [ScreenController.Effect]? {
        switch event {
            case .mirrorAttached(let mirror):
                guard (try? mirror.session.enter()) != nil else {
                    mirror.session.leave()
                    return []
                }
                mirrors.shown[mirror.id] = mirror
                let sink = sink
                mirrors.inputs[mirror.id] = Task {
                    for await input in mirror.input.events where ScreenMirror.takes(input) {
                        sink.yield(.mirrorInput(input))
                    }
                    sink.yield(.mirrorEnded(mirror.id))
                }
                mirror.input.start()
                mirror.renderer.redraw()
                mirror.renderer.submit(controller.state)
                return []
            case .mirrorInput(let input):
                controller.frame = frames.load()
                return controller.handle(input, pageRows: Swift.max(1, rows - 3), columns: columns)
            case .mirrorResized(let id):
                guard let mirror = mirrors.shown[id], let size = try? mirror.connection.getSize() else { return [] }
                mirror.renderer.resize(columns: size.columns, rows: size.rows)
                mirror.renderer.redraw()
                mirror.renderer.submit(controller.state)
                return []
            case .mirrorEnded(let id):
                await endMirror(id)
                return []
            default: return nil
        }
    }

    /// Carries out the controller's effects, then brings the timers, the lane and the frames up to date. Returns false when the
    /// screen should close.
    func settle(_ effects: [ScreenController.Effect]) async -> Bool {
        for effect in effects where await !perform(effect) {
            return false
        }
        syncProgress()
        syncLane()
        syncAutoscroll()
        render()
        return true
    }

    /// Hands every mirror the screen as it is now.
    func renderMirrors(full: Bool) {
        for mirror in mirrors.shown.values {
            if full { mirror.renderer.redraw() }
            mirror.renderer.submit(controller.state)
        }
    }

    /// Leaves every mirror's terminal as it found it.
    func endMirrors() async {
        for id in Array(mirrors.shown.keys) { await endMirror(id) }
    }

    private func endMirror(_ id: Int) async {
        guard let mirror = mirrors.shown.removeValue(forKey: id) else { return }
        mirrors.inputs.removeValue(forKey: id)?.cancel()
        mirror.input.stop()
        await mirror.renderer.finish()
        mirror.session.leave()
    }
}
