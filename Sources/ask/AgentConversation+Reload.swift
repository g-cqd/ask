internal import AskAgentCore
internal import AskTUI
internal import AskTools
internal import Foundation
internal import Synchronization

/// Reloading ask into a newer build of itself (ADR-0033).
extension AgentConversation {
    /// Tells the screen, once, that a new executable appeared beside the running one.
    func background(update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never>? {
        guard let startup else { return nil }
        return Task {
            // The first event is "a build appeared", not "a build is finished": /reload's self-check decides that.
            for await _ in BinaryWatcher.changes(since: startup) {
                update(.notice("A new ask binary appeared. /reload checks it and switches to it.", isError: false))
                break
            }
        }
    }

    /// `/reload`: check the new build, and when it works ask the screen to close so this process can be replaced.
    func reload(arguments: String, update: @Sendable (ConversationUpdate) -> Void) async {
        guard let startup else {
            update(.notice("ask cannot find its own executable, so it cannot reload.", isError: true))
            return
        }
        guard let latest = BinaryIdentity(path: startup.path), latest != startup else {
            update(
                .notice(
                    "The executable on disk is the one that is running (\(startup.summary)); nothing to reload.",
                    isError: false))
            return
        }
        let running = jobs.running
        let stopsJobs = arguments == "now"
        if !running.isEmpty, !stopsJobs {
            let list = running.joined(separator: ", ")
            update(
                .notice(
                    "Not reloading: \(running.count) job\(running.count == 1 ? " is" : "s are") running (\(list)). "
                        + "Stop \(running.count == 1 ? "it" : "them"), or use /reload now to stop and reload.",
                    isError: true))
            return
        }
        update(.notice("Checking the new build (\(latest.summary))…", isError: false))
        if case .failed(let reason) = await SelfCheck.run(latest.path, arguments: source.flags.arguments) {
            update(
                .notice(
                    "Not reloading: the new build failed its self-check: \(reason). Staying on the running build.",
                    isError: true))
            return
        }
        if stopsJobs { await jobs.stopAll() }
        reloadTarget.withLock { $0 = latest }
        update(.notice("Reloading into the new build…", isError: false))
        update(.requestExit(.reload))
    }

    /// Replaces this process with the build `/reload` chose, resuming this session. Called once the screen has
    /// closed and restored the terminal. Returns never: on success the new build is running; on failure there is
    /// no screen to say so on, so this says it on the terminal and exits, the session saved.
    func reExecute() -> Never {
        guard let target = reloadTarget.withLock({ $0 }), let startup else { fail("ask: nothing to reload.", code: 70) }
        var arguments = [target.path]
        var flags = source.flags
        if let path = session.withLock({ $0?.path }) {
            arguments += ["--resume", path]
            // A reload inherits recorded routing; it must not turn an old launch flag into fresh consent.
            flags.provider = nil
        }
        arguments += flags.arguments
        arguments += [
            "--reloaded-from", startup.summary, "--reload-started", String(Int(Date().timeIntervalSince1970 * 1_000))
        ]
        let failure = Reexec.replaceProcess(with: target.path, arguments: arguments)
        fail(
            "ask: could not start the new build (errno \(failure)). Your session is saved: run `ask --continue`.",
            code: 70)
    }
}
