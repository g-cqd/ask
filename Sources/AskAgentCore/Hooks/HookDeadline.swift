internal import Synchronization

/// Runs a hook step within the hook's ``AgentHook/deadline``, returning the fallback when the deadline expires (roadmap 0192).
enum HookDeadline {
    private enum Outcome<T: Sendable>: Sendable {
        case value(T)
        case timedOut
    }

    static func run<T: Sendable>(
        _ hook: any AgentHook,
        clock: any Clock<Duration> = ContinuousClock(),
        onTimeout: @autoclosure @escaping @Sendable () -> T,
        operation: @escaping @Sendable () async -> T
    ) async -> (value: T, timedOut: Bool) {
        guard let deadline = hook.deadline else {
            return (await operation(), false)
        }
        return await withTaskGroup(of: Outcome<T>.self) { group in
            group.addTask { .value(await operation()) }
            group.addTask {
                try? await clock.sleep(for: deadline)
                return .timedOut
            }
            let first = await group.next() ?? .timedOut
            group.cancelAll()
            switch first {
                case .value(let value): return (value, false)
                case .timedOut: return (onTimeout(), true)
            }
        }
    }

    /// Runs `operation` for `hook` at `point` within its deadline; a timeout gives `fallback` and is said through `timedOut`.
    static func ask<T: Sendable>(
        _ hook: any AgentHook,
        at point: String,
        clock: any Clock<Duration>,
        orElse fallback: @autoclosure @escaping @Sendable () -> T,
        timedOut: (AgentEvent) -> Void,
        _ operation: @escaping @Sendable () async -> T
    ) async -> T {
        let (value, expired) = await run(hook, clock: clock, onTimeout: fallback(), operation: operation)
        if expired { timedOut(.hookTimedOut(hook: hook.name, point: point)) }
        return value
    }
}
