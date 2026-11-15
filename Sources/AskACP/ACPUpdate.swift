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
            // Said only when a saved session is shown again: a prompt the person wrote then.
            case .userPrompt(let text): chunk("user_message_chunk", text)
            case .conversationName(let name):
                ["sessionUpdate": "session_info_update", "title": name.map { .string($0) } ?? .null]
            // Only when it was measured: a count that is not known is not said to be zero.
            case .context(_, let used?, let size?):
                ["sessionUpdate": "usage_update", "used": .int(Int64(used)), "size": .int(Int64(size))]
            // Decided where a turn is read (``ACPTurnReader``): a list is its members, the end and the failure end the request,
            // what became of a message sent during the turn answers that message's request, a tool call is told with its state
            // and its progress, an approval is asked of the client, what the client cannot be asked yet is declined, and a
            // notice or a compaction is told to a client that shows them.
            // @dl:accept -- a switch that names every case on purpose: the lists are the decision, and lists of cases look alike
            case .batch, .runEnded, .returnQueuedPrompts, .promptAccepted, .promptRefused, .notice: nil
            case .toolStarted, .toolFinished, .toolProgress, .askApproval, .askQuestions, .askInput: nil
            case .compacting, .compactionFinished: nil
            // Not built yet (the order of work in `development/research/serve-design-2026-11-14.md`): a job's output, which
            // comes between turns; a prompt's pictures; the commands and the lists they show.
            // @dl:accept -- a switch that names every case on purpose: the lists are the decision, and lists of cases look alike
            case .jobOutput, .promptPictures: nil
            case .skills, .choices, .choicesStale, .submitPrompt, .detail, .choiceSummary: nil
            // The status line's words for what `usage_update` says in numbers, and a context that was not measured.
            case .status, .context: nil
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

    /// A piece of a message: the person's words, the model's, or its reasoning.
    // @dl:accept -- the tests spell the same shape themselves, so that a wrong shape here is not also the one they expect
    private static func chunk(_ kind: String, _ text: String) -> JSONValue {
        ["sessionUpdate": .string(kind), "content": ["type": "text", "text": .string(text)]]
    }
}
