internal import AskAgentCore
internal import AskTUI

extension RunSettings {
    /// How the screen treats the pointer and tool output: the `ui` section over ADR-0046's defaults. A key a file did not set keeps
    /// the screen's own default, so a default changes in one place.
    var screenOptions: ScreenOptions {
        let ui = configuration.ui.value
        let defaults = ScreenOptions()
        let spinnerStyle = ui.spinner.flatMap { SpinnerStyle(rawValue: $0.rawValue) } ?? defaults.spinner
        return ScreenOptions(
            mouse: ui.mouse ?? defaults.mouse, copyOnSelect: ui.copyOnSelect ?? defaults.copyOnSelect,
            foldTools: ui.foldTools ?? defaults.foldTools,
            foldThinking: ui.foldThinking ?? defaults.foldThinking, scrollLines: ui.scrollLines ?? defaults.scrollLines,
            promptRows: ui.promptRows ?? defaults.promptRows, foldCode: ui.foldCode ?? defaults.foldCode,
            codeFoldLines: ui.codeFoldLines ?? defaults.codeFoldLines, sidebar: ui.sidebarOpen ?? defaults.sidebar,
            verbose: verbose, prompt: ui.prompt ?? defaults.prompt, tint: ui.tint ?? defaults.tint,
            separator: ui.separator ?? defaults.separator, padding: ui.padding ?? defaults.padding,
            lightBackground: Self.isLightBackground,
            localizedDurations: ui.localizedDurations ?? defaults.localizedDurations,
            spinner: spinnerStyle,
            jobAutoReturnWhenFocused: ui.jobAutoReturnWhenFocused ?? defaults.jobAutoReturnWhenFocused,
            abortTurnRequiresConfirmation: ui.abortTurnRequiresConfirmation ?? defaults.abortTurnRequiresConfirmation,
            interruptKeys: ui.interruptKeys.flatMap { InterruptKeys(rawValue: $0.rawValue) } ?? defaults.interruptKeys,
            escapeInterruptRequiresConfirmation: ui.escapeInterruptRequiresConfirmation
                ?? defaults.escapeInterruptRequiresConfirmation,
            interruptSendsQueued: ui.interruptSendsQueued.flatMap { QueuedAfterInterrupt(rawValue: $0.rawValue) }
                ?? defaults.interruptSendsQueued)
    }

    /// Whether the terminal says its background is light, from `COLORFGBG` (`15;0` is light on dark): the background is the last number, and 7 or
    /// 9 to 15 are the light ones. A terminal that does not set it is taken as dark; the kit's palette query is the better answer when it lands.
    static var isLightBackground: Bool {
        guard let value = LaunchEnvironment.values["COLORFGBG"], let last = value.split(separator: ";").last,
            let index = Int(last)
        else { return false }
        return index == 7 || (9 ... 15).contains(index)
    }
}
