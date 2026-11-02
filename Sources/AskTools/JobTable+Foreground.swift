/// The person's side of roadmap 0173.
extension JobTable {
    /// Sends every command the model is waiting on to the background; false when it waits on none.
    public func sendForegroundToBackground() -> Bool { foreground.sendToBackground() }
}
