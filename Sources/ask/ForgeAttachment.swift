internal import AskAgentCore
internal import AskTools

/// `#123` in a message (roadmap 0186), for the screen's turns and threads and for a print run alike.
enum ForgeAttachment {
    /// `text` with the pull requests and issues it names attached, read with `GITHUB_TOKEN` when it is set.
    /// `resolved` is told the `#123` that were read, for the screen to draw them as tokens.
    static func attach(_ text: String, workspace: String, resolved: (([String]) -> Void)? = nil) async -> String {
        let items = await ForgeReader.items(
            for: text,
            workspace: workspace,
            token: LaunchEnvironment.values["GITHUB_TOKEN"],
            path: LaunchEnvironment.values["PATH"]
        )
        if !items.isEmpty { resolved?(items.map { "#\($0.number)" }) }
        return ForgeReferences.attach(text, items: items)
    }
}
