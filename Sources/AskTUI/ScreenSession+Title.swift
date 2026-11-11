internal import TerminalKitIO

/// The terminal's tab: its title (note n60) and, once an action is long, its progress (notes n59 and n61). Everything is sent from
/// ``TabTitleWriter``'s thread, never this one.
extension ScreenSession {
    /// The terminal's own pointer and title again, whatever ask last set (note n13, note n60), and no busy mark.
    func giveBackTerminal() {
        if pointer != .default { try? connection.write(PointerShape.default.sequence) }
        if progressShown { titles.send(TerminalProgress.done) }
        if title != nil { titles.finish(TabTitle.restore) }
    }

    /// Sends the tab's title when it changed, saving the terminal's own first; with a spinner leading it, and OSC 9;4 where it is
    /// read, while a long action runs.
    func syncTitle() {
        let elapsed = longAction.update(working: controller.isWorking, at: .now)
        let long = elapsed.map(LongAction.isLong) ?? false
        let spinner =
            long ? elapsed.flatMap { TerminalProgress.frame(after: $0, of: controller.options.spinner.frames) } : nil
        let wanted = controller.tabTitle(spinner: spinner)
        if wanted != title {
            if title == nil { titles.send(TabTitle.save) }
            title = wanted
            titles.send(TabTitle.sequence(wanted))
        }
        if readsProgress, long != progressShown {
            progressShown = long
            titles.send(long ? TerminalProgress.working : TerminalProgress.done)
        }
    }
}
