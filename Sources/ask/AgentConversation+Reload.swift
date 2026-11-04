internal import AskAgentCore
internal import AskTUI
internal import AskTools
internal import Foundation
internal import Synchronization

/// Reloading ask into a newer build of itself (ADR-0033).
extension AgentConversation {
    /// What the screen is told while it is open: which background jobs are running, whenever that changes, and, once, that a new
    /// executable appeared beside the running one.
    func background(update: @escaping @Sendable (ConversationUpdate) -> Void) -> Task<Void, Never>? {
        let startup = startup
        let jobs = jobs
        let mcp = mcp
        let threads = threads
        return Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    for await line in mcp.notices { update(.notice(line, isError: false)) }
                }
                // A server whose resources changed: its @server: list is asked for again (roadmap 0067).
                group.addTask {
                    for await server in mcp.resourceListChanges { update(.choicesStale(command: "@" + server)) }
                }
                group.addTask {
                    for await list in jobs.changes() {
                        // Listed with the threads (roadmap 0194), which change on their own.
                        threads.setJobs(
                            list.map {
                                RunnerInfo(
                                    name: "[#" + $0.displayID + "]",
                                    detail: $0.command,
                                    id: $0.id,
                                    startedAt: $0.startedAt
                                )
                            }
                        )
                        update(.runners(threads.runners))
                    }
                }
                // One watcher for the configuration files and the executable; the screen owns this task while it shows
                // the conversation.
                group.addTask { await self.watchFiles(since: startup, update: update) }
                group.addTask { await self.showSessionColour(update: update) }
                group.addTask { await self.settleProtection(update: update) }
                await group.waitForAll()
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
                    isError: false
                )
            )
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
                    isError: true
                )
            )
            return
        }
        update(.notice("Checking the new build (\(latest.summary))…", isError: false))
        guard await signatureAllows(latest, update: update) else { return }
        if case .failed(let reason) = await SelfCheck.run(
            latest.path,
            arguments: source.flags.arguments,
            environment: LaunchEnvironment.values
        ) {
            update(
                .notice(
                    "Not reloading: the new build failed its self-check: \(reason). Staying on the running build.",
                    isError: true
                )
            )
            return
        }
        if stopsJobs { await jobs.stopAll() }
        reloadTarget.withLock { $0 = latest }
        update(.notice("Reloading into the new build…", isError: false))
        update(.requestExit(.reload))
    }

    /// Whether the new build may replace this one: signed as this one is, or this one unsigned, which is said.
    private func signatureAllows(_ latest: BinaryIdentity, update: @Sendable (ConversationUpdate) -> Void) async -> Bool
    {
        // A signed ask starts only a build signed as it is (roadmap 0153): the self-check would already run what is at the path.
        switch BuildSignature.check(latest.path, against: await LaunchSignature.running) {
            case .refused(let reason):
                update(
                    .notice(
                        "Not reloading: \(reason). Build with Scripts/build-release.sh, which signs it. Staying on the running build.",
                        isError: true
                    )
                )
                return false
            case .unsignedRunning:
                update(
                    .notice(
                        "The running build is not signed, so the new build's signature is not compared.",
                        isError: false
                    )
                )
            case .sameSigner: break
        }
        return true
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
        // What the person allowed for the session goes with it, in a file only they can read, taken once (roadmap 0159).
        let grantsPath = NSTemporaryDirectory() + "ask-reload-grants-" + UUID().uuidString + ".json"
        if (try? sessionGrants.write(to: grantsPath)) != nil { arguments += ["--reload-grants", grantsPath] }
        let failure = Reexec.replaceProcess(with: target.path, arguments: arguments)
        fail(
            "ask: could not start the new build (errno \(failure)). Your session is saved: run `ask --continue`.",
            code: 70
        )
    }
}
