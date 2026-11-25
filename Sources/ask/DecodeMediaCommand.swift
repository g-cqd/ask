internal import ArgumentParser
internal import AskTools

/// `ask decode-media`: short-lived Seatbelt-confined media decoder helper (security review 2026-11-25, N-A2 / R-DES-2).
/// Spawned by `ReadTool` under `sandbox-exec` with zero network, zero inherited environment, and read-only access solely
/// to the single verified media file copy; not listed in help because it is not invoked by a person.
struct DecodeMediaCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "decode-media",
        abstract: "Decode one image, PDF, or video in an isolated helper process for a parent ask.",
        shouldDisplay: false
    )

    func run() async {
        await MediaDecodeHost.serveStandardStreams()
    }
}
