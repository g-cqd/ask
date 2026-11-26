/// The person's side of roadmap 0173.
extension JobTable {
    /// Sends every command `owner`'s run is waiting on to the background (main's when nil, else the thread's); false when it waits
    /// on none.
    public func sendForegroundToBackground(owner: String? = nil) -> Bool { foreground.sendToBackground(owner: owner) }
}
