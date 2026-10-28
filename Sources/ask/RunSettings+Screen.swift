internal import AskAgentCore
internal import AskTUI

extension RunSettings {
    /// How the screen treats the pointer and tool output: the `ui` section over ADR-0046's defaults. A key a file did not set keeps
    /// the screen's own default, so a default changes in one place.
    var screenOptions: ScreenOptions {
        let ui = configuration.ui.value
        let defaults = ScreenOptions()
        let spinnerStyle = ui.spinner.flatMap { SpinnerStyle(rawValue: $0.rawValue) } ?? defaults.spinner
        let appearance = ui.appearance.flatMap { ScreenAppearance(rawValue: $0.rawValue) } ?? defaults.appearance
        var options = ScreenOptions(
            mouse: ui.mouse ?? defaults.mouse, copyOnSelect: ui.copyOnSelect ?? defaults.copyOnSelect,
            foldTools: ui.foldTools ?? defaults.foldTools,
            foldThinking: ui.foldThinking ?? defaults.foldThinking, scrollLines: ui.scrollLines ?? defaults.scrollLines,
            promptRows: ui.promptRows ?? defaults.promptRows, foldCode: ui.foldCode ?? defaults.foldCode,
            codeFoldLines: ui.codeFoldLines ?? defaults.codeFoldLines, sidebar: ui.sidebarOpen ?? defaults.sidebar,
            verbose: verbose, prompt: ui.prompt ?? defaults.prompt, tint: ui.tint ?? defaults.tint,
            separator: ui.separator ?? defaults.separator, padding: ui.padding ?? defaults.padding,
            lightBackground: appearance == .auto ? Self.isLightBackground : appearance == .light,
            localizedDurations: ui.localizedDurations ?? defaults.localizedDurations,
            spinner: spinnerStyle,
            jobAutoReturnWhenFocused: ui.jobAutoReturnWhenFocused ?? defaults.jobAutoReturnWhenFocused,
            abortTurnRequiresConfirmation: ui.abortTurnRequiresConfirmation ?? defaults.abortTurnRequiresConfirmation,
            interruptKeys: ui.interruptKeys.flatMap { InterruptKeys(rawValue: $0.rawValue) } ?? defaults.interruptKeys,
            escapeInterruptRequiresConfirmation: ui.escapeInterruptRequiresConfirmation
                ?? defaults.escapeInterruptRequiresConfirmation,
            interruptSendsQueued: ui.interruptSendsQueued.flatMap { QueuedAfterInterrupt(rawValue: $0.rawValue) }
                ?? defaults.interruptSendsQueued)
        options.appearance = appearance
        return options
    }

    /// The first guess at whether the terminal's background is light, used until the terminal answers its colour query (roadmap 0108).
    /// `COLORFGBG` (`15;0` is light on dark) when the terminal sets it: the background is the last number, and 7 or 9 to 15 are light.
    /// Otherwise the macOS appearance, because Apple Terminal sets no `COLORFGBG` and its default profiles follow the system.
    static var isLightBackground: Bool {
        if let value = LaunchEnvironment.values["COLORFGBG"], let last = value.split(separator: ";").last,
            let index = Int(last)
        {
            return index == 7 || (9 ... 15).contains(index)
        }
        return SystemAppearance.isLight
    }
}
