/// A tool over jobs, made from a ``JobAccess``: gives tests the initialiser that takes their clock.
protocol JobTool {
    init(access: JobAccess)
}

extension JobTool {
    /// The tool over `jobs`, with time limits on `clock`.
    init(jobs: JobTable, clock: any Clock<Duration>) { self.init(access: JobAccess(jobs: jobs, clock: clock)) }
}
