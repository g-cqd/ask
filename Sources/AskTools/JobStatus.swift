/// How a job stands.
public enum JobStatus: Sendable, Equatable, CustomStringConvertible {
    case running
    case exited(Int)
    case signalled(Int)
    /// Stopped by `job_stop`, a timeout, an abort, or ask exiting.
    case stopped
    case failedToStart(String)

    public var description: String {
        switch self {
            case .running: "running"
            case .exited(let code): "exit \(code)"
            case .signalled(let signal): "terminated by signal \(signal)"
            case .stopped: "stopped; the command and its children were stopped"
            case .failedToStart(let reason): "could not start: \(reason)"
        }
    }
}
