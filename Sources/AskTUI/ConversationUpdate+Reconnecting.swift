extension ConversationUpdate {
    /// Whether this update shows the model answering again after a dropped connection, which ends `Reconnecting...`.
    var showsTheModelIsBack: Bool {
        switch self {
            case .assistantText, .thinkingText, .toolStarted, .toolFinished, .status: true
            default: false
        }
    }
}
