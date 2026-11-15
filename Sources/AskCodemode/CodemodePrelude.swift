/// The JavaScript that builds a script's surface inside the VM (ADR-0156): `tools`, `ALL_TOOLS`, `text`, `console`, `exit`. It
/// holds the bridge's functions in a closure and leaves nothing of them on the global object; what it defines cannot be
/// replaced by a script.
enum CodemodePrelude {
    /// A function taking the bridge (`call`, `emit`, `exit`, `done`, `fail`) and the tools, and returning what runs a script.
    static let source = """
        (function (bridge, list) {
          "use strict";
          const stringify = (value) => {
            if (typeof value === "string") return value;
            try { const said = JSON.stringify(value); return said === undefined ? String(value) : said; }
            catch (error) { return String(value); }
          };
          const tools = Object.create(null);
          for (const tool of list) {
            const invoke = (args) => bridge.call(tool.name, JSON.stringify(args === undefined ? {} : args));
            tools[tool.name] = invoke;
            tools[tool.identifier] = invoke;
          }
          const fixed = (name, value) => Object.defineProperty(globalThis, name, { value, writable: false, configurable: false });
          const line = (...values) => { bridge.emit(true, values.map(stringify).join(" ")); };
          fixed("tools", Object.freeze(tools));
          fixed("ALL_TOOLS", Object.freeze(list.map((tool) => Object.freeze({ name: tool.identifier, description: tool.description }))));
          fixed("text", (value) => { bridge.emit(false, stringify(value)); });
          fixed("console", Object.freeze({ log: line, info: line, warn: line, error: line, debug: line }));
          fixed("exit", () => { bridge.exit(); throw new Error("exit"); });
          delete globalThis.WebAssembly;
          return (script) => script().then(
            (value) => { if (value !== undefined) bridge.emit(false, stringify(value)); bridge.done(); },
            (error) => { bridge.fail(error); });
        })
        """
}
