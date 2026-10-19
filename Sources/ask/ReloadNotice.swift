/// What a process started by `/reload` knows about the one it replaced.
struct ReloadNotice {
    /// The old build, as ``BinaryIdentity/summary`` described it.
    var from: String
    /// When the reload began, in milliseconds since the epoch.
    var startedMilliseconds: Int
}
