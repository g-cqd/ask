internal import AemiJSON

/// Encodes a ``ModelRequest`` as a Cloud Code streaming request: the `v1internal` envelope around a Gemini `generateContent` body.
///
/// - ask's instructions travel as one `systemInstruction`;
/// - a user turn is its tool results, each a `functionResponse` carrying the call's id and name, then its text; an assistant turn is
///   its text and calls in the order the model wrote them. Every call and every result carries the call's id, which Claude and GPT-OSS
///   refuse a result without (ADR-0080);
/// - reasoning is never sent, with one exception: the signature a Gemini 3 call was issued, which goes back on that call (ADR-0090).
public enum AgyRequestEncoder {
    /// The request body.
    /// - Parameters:
    ///   - request: what to ask.
    ///   - project: the account's Cloud Code project.
    ///   - requestID: an id for this request.
    ///   - promptID: an id for the prompt it belongs to.
    /// - Returns: the JSON body.
    /// - Throws: ``ThinkingError/unsupportedProtocol(_:)`` when the request asks for an explicit thinking control, which this protocol
    ///   has no tested way to carry.
    public static func encode(_ request: ModelRequest, project: String, requestID: String, promptID: String)
        throws(ThinkingError) -> [UInt8]
    {
        if request.thinking != nil { throw .unsupportedProtocol("Antigravity") }
        let contents = Content.all(in: request)
        var writer = JSONStreamWriter(capacity: 4_096)
        writer.object { writer in
            writer.field("project", project)
            writer.field("requestId", requestID)
            writer.field("model", request.model)
            writer.field("userAgent", AgyCloud.userAgent)
            writer.field("requestType", "agent")
            writer.field("userPromptId", promptID)
            writer.key("request")
            writer.object { writer in
                writer.key("contents")
                writer.array { writer in for content in contents { content.write(into: &writer) } }
                if !request.systemPrompt.isEmpty {
                    writer.key("systemInstruction")
                    writer.object { writer in
                        writer.key("parts")
                        writer.array { $0.object { $0.field("text", request.systemPrompt.joined(separator: "\n\n")) } }
                    }
                }
                if !request.tools.isEmpty { writeTools(request.tools, into: &writer) }
                writer.key("generationConfig")
                writer.object { writer in
                    writer.field("maxOutputTokens", request.maxTokens)
                    writer.key("thinkingConfig")
                    writer.object { $0.field("includeThoughts", true) }
                }
            }
        }
        return writer.finish()
    }

    private static func writeTools(_ tools: [ToolDefinition], into writer: inout JSONStreamWriter) {
        writer.key("tools")
        writer.array { writer in
            writer.object { writer in
                writer.key("functionDeclarations")
                writer.array { writer in
                    for tool in tools {
                        writer.object { writer in
                            writer.field("name", tool.name)
                            writer.field("description", tool.description)
                            writer.key("parametersJsonSchema")
                            writer.raw(tool.inputSchema.bytes)
                        }
                    }
                }
            }
        }
        writer.key("toolConfig")
        writer.object { writer in
            writer.key("functionCallingConfig")
            writer.object { $0.field("mode", "AUTO") }
        }
    }
}
