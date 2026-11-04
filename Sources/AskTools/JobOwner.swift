/// Who a job is started for (roadmap 0195): a thread's run sets its name, so the jobs its commands start are listed under it.
/// Task-local, so every tool call of the run starts its jobs for it, however deep in the run's tasks.
public enum JobOwner {
    @TaskLocal public static var current: String?
}
