internal import ArgumentParser
internal import AskCodemode

/// `ask codemode`: the process that hosts one script's VM (ADR-0156). ask runs this as a child of itself for each script, and
/// speaks to it on its standard streams; it is not listed in the help because it is not for a person. It reaches nothing by
/// itself: a script's only way out is the tools, which the parent runs.
struct CodemodeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "codemode",
        abstract: "Host one codemode script for a parent ask, on standard input and output.",
        shouldDisplay: false
    )

    @Option(help: "The most memory the process may take before it ends itself, in MiB.")
    var memory = 256

    func run() async {
        await CodemodeHost.serveStandardStreams(memoryLimit: max(32, memory) << 20)
    }
}
