internal import ArgumentParser
internal import AskSession
internal import AskTools
internal import Foundation

/// `ask forge DIRECTORY`: the directory's GitHub repository as ask shows it (its open pull requests and issues, its branch's pull
/// request), printed as JSON. ask runs this as a child of itself (ADR-0152), so the network stack a request loads ends with the
/// child; it is not listed in the help because it is not for a person, and nothing in it is secret.
struct ForgeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "forge",
        abstract: "Print a directory's open pull requests and issues, and its branch's pull request, as JSON.",
        shouldDisplay: false
    )

    @Argument(help: "The directory whose repository is read.")
    var directory: String

    func run() async {
        let values = LaunchEnvironment.values
        let snapshot = await ForgeSnapshot.read(
            workspace: directory,
            token: values["GITHUB_TOKEN"],
            path: values["PATH"]
        )
        FileHandle.standardOutput.write(Data(snapshot.encoded() + [0x0A]))
    }
}
