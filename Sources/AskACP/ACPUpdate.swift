internal import AemiJSON
internal import AskTUI

/// What a conversation says, as ACP's `session/update` (ADR-0154): each of the conversation's updates is decided once, here. The
/// switch has no default, so a new update does not compile until it is given a place: sent, or in the list of what is not.
enum ACPUpdate {
    /// The `update` of a `session/update` for `update`, or nil for what is not sent.
    static func payload(for update: ConversationUpdate) -> JSONValue? {
        switch update {
            case .assistantText(let text): chunk("agent_message_chunk", text)
            case .thinkingText(let text): chunk("agent_thought_chunk", text)
            // Decided where a turn is read (``ACPTurns``): a list is its members, the end and the failure end the request, and
            // what became of a message sent during the turn answers that message's request.
            // @dl:accept -- a switch that names every case on purpose: the lists are the decision, and lists of cases look alike
            case .batch, .runEnded, .returnQueuedPrompts, .promptAccepted, .promptRefused, .notice: nil
            // Not built yet (the order of work in `development/research/serve-design-2026-11-14.md`): tool calls, approvals and
            // questions, the replay of a session, compaction, usage, the name, the commands.
            // @dl:accept -- a switch that names every case on purpose: the lists are the decision, and lists of cases look alike
            case .toolStarted, .toolFinished, .toolProgress, .jobOutput, .askApproval, .askQuestions, .askInput: nil
            case .userPrompt, .promptPictures, .compacting, .compactionFinished, .status, .context, .conversationName:
                nil
            case .skills, .choices, .choicesStale, .submitPrompt, .detail, .choiceSummary: nil
            // The screen's furniture, which no client is sent (ADR-0154): the status line's segments, the pickers' rows, drafts,
            // the configuration editor, runners, threads and asides.
            case .sessionIdentity, .label, .labelVariants, .gitStatus, .branchPullRequest, .referencesResolved: nil
            case .requestExit, .fillDraft, .editDraft, .clearConversation, .pictureAttached, .promptWithdrawn,
                .besideEnded:
                nil
            case .runners, .runnerActivity, .runnerOutput, .files, .configEditor, .sandboxActive: nil
            case .reconnecting, .connectingMCP, .waitingForNetwork: nil
            case .asideStarted, .asideFinished, .threadStarted, .threadMerged, .focusThread, .thread: nil
        }
    }

    /// A piece of a message: the model's words, or its reasoning.
    private static func chunk(_ kind: String, _ text: String) -> JSONValue {
        ["sessionUpdate": .string(kind), "content": ["type": "text", "text": .string(text)]]
    }
}
