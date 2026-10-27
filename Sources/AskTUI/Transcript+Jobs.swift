extension Transcript {
    /// Replace only the originating tool, never the newest unrelated tool. Fold choices remain keyed to its index.
    mutating func updateJob(_ job: JobUpdate, at instant: ContinuousClock.Instant = .now) {
        guard let index = jobBlocks[job.id], !completedJobs.contains(job.id),
            case .tool(let name, let summary, _, _) = items[index]
        else { return }
        let prefix = "[\(job.label)] "
        let title = summary.hasPrefix(prefix) ? summary : prefix + summary
        items[index] = .tool(name: name, summary: title, status: job.status, output: Self.kept(job.output))
        var clock = BlockProgress(at: job.startedAt, spinner: progress[index]?.spinner ?? spinnerStyle)
        clock.sampled = instant
        clock.ended = job.endedAt
        clock.frame = progress[index]?.frame ?? 0
        progress[index] = clock
        revisions[index] = bump()
        guard job.status != .running else { return }
        clock.ended = job.endedAt ?? instant
        progress[index] = clock
        completedJobs.insert(job.id)
        append(.jobEnded(label: "[\(job.label)] \(job.ending)", status: job.status, lines: job.lines))
        progress[items.count - 1] = clock
    }
}
