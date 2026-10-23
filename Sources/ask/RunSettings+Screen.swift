internal import AskAgentCore
internal import AskTUI

extension RunSettings {
    /// How the screen treats the pointer and tool output: the `ui` section over ADR-0046's defaults. A key a file did not set keeps
    /// the screen's own default, so a default changes in one place.
    var screenOptions: ScreenOptions {
        let ui = configuration.ui.value
        let defaults = ScreenOptions()
        return ScreenOptions(
            mouse: ui.mouse ?? defaults.mouse, copyOnSelect: ui.copyOnSelect ?? defaults.copyOnSelect,
            foldTools: ui.foldTools ?? defaults.foldTools,
            foldThinking: ui.foldThinking ?? defaults.foldThinking, scrollLines: ui.scrollLines ?? defaults.scrollLines,
            promptRows: ui.promptRows ?? defaults.promptRows, foldCode: ui.foldCode ?? defaults.foldCode,
            codeFoldLines: ui.codeFoldLines ?? defaults.codeFoldLines)
    }
}
