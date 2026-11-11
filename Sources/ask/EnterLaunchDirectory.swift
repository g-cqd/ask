internal import AskCore
internal import Foundation

/// Before anything reads the working directory: when the process has none, because the shell's was replaced under it, go back to
/// the one the shell names, and say so; with nowhere to go, stop (``LaunchDirectory``).
///
/// Stopping is a refusal, and its reason is this: with no working directory the project is the empty path, so the session would be
/// filed under no project, the project's configuration would not be read, and no command could start. The usual launch pays one
/// `getcwd` here, which it made anyway a little later.
func enterLaunchDirectory() {
    let current = FileManager.default.currentDirectoryPath
    guard current.isEmpty else { return }
    let resolution = LaunchDirectory.resolve(current: current, shell: LaunchEnvironment.values["PWD"]) { path in
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
    if case .enter(let path) = resolution, FileManager.default.changeCurrentDirectoryPath(path) {
        FileHandle.standardError.write(
            Data(
                "ask: this shell's directory was replaced under it (removed, or its volume mounted again); working in \(path).\n"
                    .utf8
            )
        )
        return
    }
    fail(
        "ask: the directory this shell is in is not there any more (removed, or its volume mounted again), so ask has nowhere to "
            + "work. Go to your project again (cd \"$PWD\" often does it) and start ask there.",
        code: 71
    )
}
