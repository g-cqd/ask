internal import AskAI
internal import Foundation
internal import FoundationModels

/// One request to the on-device model: what to offer, how much of the conversation fits, and the events the loop reads.
struct AppleRun {
    let request: ModelRequest

    func run(_ emit: (ModelEvent) -> Void) async throws {
        if case .unavailable(let reason) = AppleModel.availability() {
            throw ProviderFailure(
                kind: .notFound,
                message: "The on-device model is unavailable: \(reason). /login signs in to another provider.")
        }
        let window = AppleModel.contextWindow
        let budget = AppleBudget(window: window, requested: request.maxTokens)
        let capture = AppleCapture()
        let offered = tools(within: budget.toolTokens, capture: capture)
        let instructed = ApplePrompt.instructions(
            request.systemPrompt,
            budget: budget.instructionTokens(tools: offered.tokens) * ApplePrompt.charactersPerToken)
        let instructions = Self.hint(hasTools: !offered.tools.isEmpty) + instructed.text
        let used = ApplePrompt.estimatedTokens(instructions)
        let room = budget.conversationTokens(instructions: used, tools: offered.tokens)
        let prompt = await fitted(
            ApplePrompt.turns(request.messages), instructions: instructions, tools: offered.tools, budget: budget,
            tokens: room)
        let session = LanguageModelSession(model: .default, tools: offered.tools, instructions: instructions)
        let options = GenerationOptions(maximumResponseTokens: budget.reply)
        let inputTokens = used + offered.tokens + ApplePrompt.estimatedTokens(prompt)

        emit(
            .messageStarted(
                id: "apple_" + UUID().uuidString.prefix(8).lowercased(), model: request.model,
                usage: TokenUsage(input: inputTokens)))
        var text = ""
        var block: Int?
        do {
            for try await snapshot in session.streamResponse(to: prompt, options: options) {
                let current = snapshot.content
                guard current.count > text.count, current.hasPrefix(text) else { continue }
                if block == nil {
                    block = 0
                    emit(.blockStarted(index: 0, .text))
                }
                emit(.textDelta(index: 0, String(current.dropFirst(text.count))))
                text = current
            }
        } catch {
            // A call the model made ends the response by design; only a failure with no call is one.
            guard capture.call != nil else { throw error }
        }
        if block != nil { emit(.blockStopped(index: 0)) }
        var reason = StopReason.endTurn
        if let call = capture.call {
            let index = block == nil ? 0 : 1
            emit(.blockStarted(index: index, .toolUse(id: call.id, name: call.name)))
            emit(.toolInputDelta(index: index, call.arguments))
            emit(.blockStopped(index: index))
            reason = .toolUse
        }
        emit(.messageDelta(stopReason: reason, usage: TokenUsage(output: ApplePrompt.estimatedTokens(text))))
        emit(.messageStopped)
    }

    /// The tools that fit `tokens`, in the order the loop lists them, with what they cost and what was left out. Every tool is tried with its
    /// whole description first, then with its first sentence, and only then are tools dropped from the end.
    private func tools(within tokens: Int, capture: AppleCapture) -> (tools: [any Tool], tokens: Int, notes: [String]) {
        for detail in [AppleToolSchema.Detail.full, .brief] {
            let built = request.tools.compactMap { definition -> (ToolDefinition, GenerationSchema, Int)? in
                guard
                    let schema = AppleToolSchema.schema(
                        named: definition.name, description: definition.description,
                        inputSchema: definition.inputSchema.bytes, detail: detail)
                else { return nil }
                return (
                    definition, schema,
                    AppleToolSchema.footprint(of: definition, detail: detail) / ApplePrompt.charactersPerToken + 8
                )
            }
            var kept = built[...]
            // Whole descriptions are all or nothing; only first sentences may cost tools.
            if detail == .brief {
                while kept.reduce(0, { $0 + $1.2 }) > tokens, !kept.isEmpty { kept = kept.dropLast() }
            }
            let total = kept.reduce(0) { $0 + $1.2 }
            guard total <= tokens else { continue }
            let tools = kept.map { definition, schema, _ in
                AppleCapturingTool(
                    name: definition.name,
                    description: AppleToolSchema.clipped(definition.description, limit: detail.limit) ?? "",
                    parameters: schema, capture: capture)
            }
            let dropped = built.dropFirst(kept.count).map(\.0.name)
            var notes: [String] = []
            if detail == .brief { notes.append("The on-device window held the tools' first sentences only.") }
            if !dropped.isEmpty {
                notes.append(
                    "The on-device window held \(kept.count) of \(built.count) tools; left out: \(dropped.joined(separator: ", "))."
                )
            }
            return (tools, total, notes)
        }
        return ([], 0, ["The on-device window held no tools."])
    }

    /// The conversation that fits `tokens`: estimated first, then, where the system can count, checked and cut again until it fits.
    private func fitted(
        _ turns: [String], instructions: String, tools: [any Tool], budget: AppleBudget, tokens: Int
    ) async -> String {
        var allowed = tokens
        var prompt = ApplePrompt.fit(turns, budget: allowed * ApplePrompt.charactersPerToken)
        guard #available(macOS 26.4, *) else { return prompt }
        for _ in 0 ..< 3 {
            guard let counted = try? await Self.count(instructions: instructions, tools: tools, prompt: prompt),
                counted + budget.reply > budget.window
            else { break }
            allowed = Swift.max(64, allowed * (budget.window - budget.reply) / Swift.max(1, counted) - 16)
            prompt = ApplePrompt.fit(turns, budget: allowed * ApplePrompt.charactersPerToken)
        }
        return prompt
    }

    /// The window's real use, as the system counts it. Available from macOS 26.4.
    @available(macOS 26.4, *)
    private static func count(instructions: String, tools: [any Tool], prompt: String) async throws -> Int {
        let model = SystemLanguageModel.default
        return try await model.tokenCount(for: Instructions(instructions)) + model.tokenCount(for: tools)
            + model.tokenCount(for: prompt)
    }

    /// One line, ahead of ask's own instructions, that tells a small model when a tool is for.
    private static func hint(hasTools: Bool) -> String {
        hasTools
            ? "Answer in plain text. Call a tool only when the task needs a file read, a file changed or a command run.\n\n"
            : ""
    }
}
