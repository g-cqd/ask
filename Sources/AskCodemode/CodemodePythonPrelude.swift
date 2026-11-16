/// The Python that builds a script's surface and runs it (ADR-0156): the script's end of the bridge, where JavaScript has
/// ``CodemodePrelude`` and ``CodemodeHost``. It is given to a `python3` with `-c`, and speaks ``CodemodeWire``'s messages on
/// its standard streams: asked `run` once, it asks `call` for each tool and answers with what the script came to.
///
/// The script is the body of an `async def`: `await tools.name(key=value)`, `text(...)`, `print(...)` for the console, `return`.
/// Nothing here keeps a script in: the profile its process runs under does (the tools' `CodemodePython`).
package enum CodemodePythonPrelude {
    /// The whole program: the surface a script is given, then what runs the script and speaks to ask.
    package static let source = surface + "\n\n" + running

    /// The limits these lines hold are ``CodemodeVM``'s, which a test compares them with.
    // @dl:accept -- two halves of one Python program, each a long string: to the analyzer a long string is like any other
    static let surface = #"""
        import ast, asyncio, io, json, os, resource, sys, threading, time

        FILE = "codemode.py"
        MAXIMUM_CHARACTERS = 1048576
        MAXIMUM_ITEMS = 10000
        # Kept for the life of the process: sys.stdout is replaced below, and a text stream nobody holds closes its pipe.
        standard = (sys.stdin, sys.stdout, sys.stderr)
        bridge_in, bridge_out = sys.stdin.buffer, sys.stdout.buffer

        class ToolError(Exception):
            """A tool call that failed: its message is the tool's own words."""

        class Stopped(BaseException):
            """Unwinds a script whose result is already fixed."""

        class State:
            items, characters, ended, failure, pending, calls, loop = 0, 0, False, None, {}, 0, None

        def send(message):
            bridge_out.write(json.dumps(message, ensure_ascii=False).encode("utf-8", "replace") + b"\n")
            bridge_out.flush()

        def finish(failure):
            if not State.ended:
                State.ended, State.failure = True, failure

        def emit(text, console):
            if State.ended:
                return
            if State.items >= MAXIMUM_ITEMS:
                finish("The script made more than %d text and print calls." % MAXIMUM_ITEMS)
                raise Stopped()
            if State.characters + len(text) > MAXIMUM_CHARACTERS:
                said_too_much = "The script said more than %d characters; write large data to a file with a tool instead."
                finish(said_too_much % MAXIMUM_CHARACTERS)
                raise Stopped()
            State.characters += len(text)
            State.items += 1
            # Told as it is said: a script that is stopped keeps what it had said.
            send({"jsonrpc": "2.0", "method": "said", "params": {"text": text, "console": console}})

        def said(value):
            if isinstance(value, str):
                return value
            if isinstance(value, (dict, list, tuple)):
                try:
                    return json.dumps(value, ensure_ascii=False, default=str)
                except (TypeError, ValueError):
                    pass
            return str(value)

        class Console(io.TextIOBase):
            """Where print() and what is written to sys.stdout and sys.stderr go: a line an item."""

            def __init__(self):
                self.partial = ""

            def writable(self):
                return True

            def write(self, text):
                self.partial += text
                while "\n" in self.partial:
                    line, self.partial = self.partial.split("\n", 1)
                    emit(line, True)
                return len(text)

            def end(self):
                if self.partial:
                    line, self.partial = self.partial, ""
                    emit(line, True)

        def identifier(name):
            made = "".join(c if c.isascii() and (c.isalnum() or c == "_") else "_" for c in name) or "_"
            return "_" + made if made[0].isdigit() else made

        class Tools:
            def __init__(self, listed):
                names = {}
                for tool in listed:
                    names[tool["name"]] = names[identifier(tool["name"])] = tool["name"]
                object.__setattr__(self, "_names", names)

            def _named(self, name):
                if name not in self._names:
                    raise AttributeError("No tool is named %s; ALL_TOOLS lists them." % name)
                tool = self._names[name]
                return lambda *positional, **arguments: call(tool, positional, arguments)

            def __getattr__(self, name):
                return self._named(name)

            def __getitem__(self, name):
                return self._named(name)

            def __setattr__(self, name, value):
                raise AttributeError("tools cannot be changed")

        def call(tool, positional, arguments):
            if positional:
                if len(positional) != 1 or not isinstance(positional[0], dict) or arguments:
                    raise TypeError("%s takes its arguments by keyword, or as one dict" % tool)
                arguments = positional[0]
            encoded = json.dumps(arguments)
            future = State.loop.create_future()
            if State.ended:
                return future
            State.calls += 1
            State.pending[State.calls] = future
            send({"jsonrpc": "2.0", "id": State.calls, "method": "call", "params": {"tool": tool, "arguments": encoded}})
            return future
        """#
}
