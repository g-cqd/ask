/// Something running beside the conversation that the status line counts and `/tasks` lists: today a background job, later a subagent.
public struct RunnerInfo: Sendable, Equatable {
    /// How the model and the user name it, such as `job-3`.
    public var name: String
    /// What it is doing, such as the command line. Line breaks are shown as spaces.
    public var detail: String

    public init(name: String, detail: String) {
        self.name = name
        self.detail = detail
    }
}
