internal import AskMCP

/// Lists each MCP server's process group with the job watchdog, so a SIGKILL or a crash of ask does not leave the server running
/// (ADR-0102), exactly as it does not leave a job.
struct WatchdogObserver: StdioProcessObserver {
    let watchdog: JobWatchdog

    func started(group: Int32) { watchdog.watch(group) }
    func ended(group: Int32) { watchdog.release(group) }
}
