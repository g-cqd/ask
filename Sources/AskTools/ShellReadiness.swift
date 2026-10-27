internal import AskAgentCore
internal import Foundation

/// Readiness policy shared by new launches and existing-job waits; file/port observations remain sandboxed.
enum ShellReadiness: Sendable {
    case output(String)
    case port(Int)
    case file(String)

    static func select(output: String?, port: Int?, file: String?, in context: ToolContext) throws(ToolFailure) -> Self?
    {
        guard [output != nil, port != nil, file != nil].filter({ $0 }).count <= 1 else {
            throw ToolFailure("Choose only one of wait_for_output, wait_for_port or wait_for_file.")
        }
        if let output {
            guard !output.isEmpty else { throw ToolFailure("wait_for_output must not be empty.") }
            return .output(output)
        }
        if let port {
            guard (1 ... 65_535).contains(port) else { throw ToolFailure("wait_for_port must be between 1 and 65535.") }
            guard context.sandbox.network != .none else { throw ToolFailure("Port readiness is not permitted.") }
            return .port(port)
        }
        if let file {
            guard !file.isEmpty else { throw ToolFailure("wait_for_file must not be empty.") }
            _ = try FileTools.authorized(file, for: [.read], in: context)
            return .file(file)
        }
        return nil
    }

    /// First of readiness, process completion, timeout or cancellation. No output is consumed here.
    func wait(for job: Job, seconds: Int, clock: any Clock<Duration>, in context: ToolContext)
        async throws(ToolFailure) -> JobWaiting.Outcome
    {
        if case .output(let text) = self {
            return await JobWaiting.wait(for: job, needle: Array(text.utf8), seconds: seconds, clock: clock)
        }
        let path: String?
        if case .file(let file) = self {
            path = try FileTools.authorized(file, for: [.read], in: context).path
        } else {
            path = nil
        }
        let result = await withTaskGroup(of: JobWaiting.Outcome?.self) { group in
            group.addTask {
                if let path { return await FileWait.until(exists: path) ? .found : nil }
                if case .port(let port) = self { return await PortWait.until(open: port, clock: clock) ? .found : nil }
                return nil
            }
            group.addTask { await JobWaiting.watch(job, for: nil) }
            group.addTask { await JobWaiting.expiry(after: seconds, on: clock) }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .cancelled
        }
        if case .file(let file) = self {
            let url = try FileTools.authorized(file, for: [.read], in: context)
            if result == .found {
                guard try ScopedFile.exists(url, shownAs: file, in: context) else {
                    throw ToolFailure("\(file) disappeared before readiness could be verified.")
                }
            } else if result == .cancelled, !Task.isCancelled {
                throw ToolFailure("Cannot watch \(file).")
            }
        }
        return result
    }

    var headline: String {
        if case .output(let text) = self { return "printed \"\(text)\"" }
        if case .port(let port) = self { return "port \(port) accepts connections" }
        if case .file(let file) = self { return "\(file) exists" }
        return ""
    }
}
