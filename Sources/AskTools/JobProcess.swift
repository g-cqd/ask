internal import Foundation
internal import Subprocess
internal import System

internal import struct AskAgentCore.SandboxPolicy
internal import struct AskAgentCore.SeatbeltProfile

/// How a job's process is started: bash in its own session, torn down as a group, its output file created
/// owner-only.
enum JobProcess {
    /// bash running the job's command in its own session. Teardown: SIGTERM to the group, two seconds, then
    /// SIGKILL to the group.
    ///
    /// Under a policy that restricts anything, bash runs inside `sandbox-exec` with the policy's Seatbelt profile, which
    /// `exec`s bash so the group teardown still reaches it. Without one, bash is started directly and costs nothing.
    static func configuration(_ launch: Job.Launch) -> Configuration {
        var arguments = ["-c", launch.command]
        var executable = "/bin/bash"
        if !launch.sandbox.isUnrestricted {
            arguments = SeatbeltProfile(launch.sandbox).arguments + ["/bin/bash"] + arguments
            executable = "/usr/bin/sandbox-exec"
        }
        return Configuration(
            executable: .path(FilePath(executable)), arguments: Arguments(arguments),
            environment: .custom(
                Dictionary(
                    uniqueKeysWithValues: launch.environment.compactMap { name, value in
                        // `=` and NUL cannot occur in an environment entry's name.
                        isEntryName(name) ? Environment.Key(rawValue: name).map { ($0, value) } : nil
                    })),
            workingDirectory: FilePath(launch.workingDirectory), platformOptions: groupOptions(graceSeconds: 2))
    }

    /// Whether `name` can be the name of an environment entry.
    private static func isEntryName(_ name: String) -> Bool {
        !name.utf8.contains(0x3D) && !name.utf8.contains(0)
    }

    /// Own session, and a teardown that reaches every process the command started: SIGTERM to the group, `graceSeconds`
    /// to stop, then SIGKILL to the group. Shared by jobs and by the self-check of a new build.
    static func groupOptions(graceSeconds: Int) -> PlatformOptions {
        var options = PlatformOptions()
        options.createSession = true
        options.teardownSequence = [
            .gracefulShutDown(toProcessGroup: true, allowedDurationToNextStep: .seconds(graceSeconds)),
            .send(signal: .kill, toProcessGroup: true, allowedDurationToNextStep: .seconds(1))
        ]
        return options
    }

    /// A new, owner-only file at `path`, in a directory created owner-only if needed; nil if it cannot be made.
    static func createFile(_ path: String) -> FileDescriptor? {
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return try? FileDescriptor.open(
            FilePath(path), .writeOnly, options: [.create, .exclusiveCreate], permissions: [.ownerReadWrite])
    }
}
