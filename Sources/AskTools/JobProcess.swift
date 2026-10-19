internal import Foundation
internal import Subprocess
internal import System

/// How a job's process is started: bash in its own session, torn down as a group, its output file created
/// owner-only.
enum JobProcess {
    /// bash running the job's command in its own session. Teardown: SIGTERM to the group, two seconds, then
    /// SIGKILL to the group.
    static func configuration(_ launch: Job.Launch) -> Configuration {
        var options = PlatformOptions()
        options.createSession = true
        options.teardownSequence = [
            .gracefulShutDown(toProcessGroup: true, allowedDurationToNextStep: .seconds(2)),
            .send(signal: .kill, toProcessGroup: true, allowedDurationToNextStep: .seconds(1))
        ]
        return Configuration(
            executable: .path("/bin/bash"), arguments: ["-c", launch.command],
            workingDirectory: FilePath(launch.workingDirectory), platformOptions: options)
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
