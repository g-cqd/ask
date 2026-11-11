/// A click on a link (roadmaps 0075 and 0216).
extension ScreenSession {
    /// Opens `uri` as the person's openers say: their command, asked about first by the conversation, or the app or the system's
    /// own way, whose notice goes to the status line.
    func open(_ uri: String) {
        let opening = conversation.opening(for: uri)
        guard LinkOpener.runsCommand(uri, opening: opening) else {
            if let notice = LinkOpener.perform(uri, opening: opening) { controller.state.clipboardNotice = notice }
            return
        }
        // The command's question would take the place of the one waiting, whose run would then wait for ever.
        guard controller.state.pendingApproval == nil else {
            controller.state.clipboardNotice = "Not run: answer the question first."
            return
        }
        let sink = sink
        conversation.runOpener(for: uri) { sink.yield(.update($0)) }
    }
}
