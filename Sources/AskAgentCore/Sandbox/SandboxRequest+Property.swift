public import AskAI

extension SandboxRequest {
    /// The `sandbox` argument as the model is told about it, declared by the tools that honour it.
    public static let property = declared(session: false)

    /// The same argument with `session`, declared where a model asks the sandbox for anything: on the command (ADR-0162).
    public static let propertyWithSession = declared(session: true)

    private static func declared(session: Bool) -> ToolProperty {
        let says =
            "Narrow this call's sandbox; it cannot widen it. network: none, localhost, provider or any. "
            + "write, read: paths relative to the working directory."
            + (session
                ? " session: keep holds it for every later call (stop jobs first); reset asks the person to undo that."
                : "")
        let paths = #"{"type":"array","items":{"type":"string"}}"#
        let fields =
            #""network":{"type":"string","enum":["none","localhost","provider","any"]},"write":\#(paths),"read":\#(paths)"#
            + (session ? #","session":{"type":"string","enum":["keep","reset"]}"# : "")
        return ToolProperty.schema("sandbox", #"{"type":"object","description":"\#(says)","properties":{\#(fields)}}"#)
            .optional
    }
}
