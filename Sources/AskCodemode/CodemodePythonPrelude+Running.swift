/// The second half of the Python prelude: what runs a script and speaks to ask.
extension CodemodePythonPrelude {
    // @dl:accept -- two halves of one Python program, each a long string: to the analyzer a long string is like any other
    static let running = #"""
        def describe(error):
            line, frame = None, error.__traceback__
            while frame is not None:
                if frame.tb_frame.f_code.co_filename == FILE:
                    line = frame.tb_lineno
                frame = frame.tb_next
            words = "%s: %s" % (type(error).__name__, error) if str(error) else type(error).__name__
            return words if line is None else "%s (%s:%d)" % (words, FILE, line)

        def leave(code=None):
            raise SystemExit(code)

        async def run(request):
            parameters = request.get("params") or {}
            console = Console()
            sys.stdout = sys.stderr = sys.__stdout__ = sys.__stderr__ = console
            sys.stdin = sys.__stdin__ = io.StringIO("")
            try:
                body = ast.parse(parameters.get("code", ""), FILE).body
                module = ast.parse("async def __script__():\n    pass", FILE)
                if body:
                    module.body[0].body = body
                compiled = compile(module, FILE, "exec")
            except SyntaxError as error:
                finish("SyntaxError: %s (%s:%s)" % (error.msg, FILE, error.lineno))
            else:
                listed = parameters.get("tools") or []
                scope = {
                    "__name__": "__codemode__", "tools": Tools(listed), "text": lambda value: emit(said(value), False),
                    "ALL_TOOLS": tuple(
                        {"name": identifier(t["name"]), "description": t.get("description", "")} for t in listed
                    ),
                    "ToolError": ToolError, "asyncio": asyncio, "json": json, "exit": leave, "quit": leave,
                }
                try:
                    exec(compiled, scope)
                    value = await scope["__script__"]()
                    console.end()
                    if value is not None:
                        emit(said(value), False)
                    finish(None)
                except Stopped:
                    pass
                except SystemExit as error:
                    console.end() if not State.ended else None
                    finish(None if error.code in (None, 0) else "SystemExit: %s" % (error.code,))
                except BaseException as error:  # noqa: a script may raise anything
                    try:
                        console.end()
                    except Stopped:
                        pass
                    finish(describe(error))
            result = {"items": State.items, "unsettled": sum(1 for f in State.pending.values() if not f.done())}
            if State.failure is not None:
                result["failure"] = State.failure
            send({"jsonrpc": "2.0", "id": request.get("id"), "result": result})

        def receive(line):
            try:
                message = json.loads(line)
            except ValueError:
                return
            if not isinstance(message, dict):
                return
            if message.get("method") == "run":
                State.loop.create_task(run(message))
            elif "method" not in message:
                future = State.pending.get(message.get("id"))
                if future is None or future.done():
                    return
                if "error" in message:
                    future.set_exception(ToolError((message["error"] or {}).get("message", "The call failed.")))
                else:
                    future.set_result((message.get("result") or {}).get("text", ""))

        def read():
            for line in bridge_in:
                State.loop.call_soon_threadsafe(receive, line)
            os._exit(0)  # the parent has gone, or has what it asked for

        def watch(limit):
            # Python has no limit on what a script allocates. One allocation larger than the limit is seen once made.
            while resource.getrusage(resource.RUSAGE_SELF).ru_maxrss <= limit:
                time.sleep(0.002)
            os._exit(86)

        asyncio.log.logger.disabled = True
        if len(sys.argv) > 1:
            threading.Thread(target=watch, args=(int(sys.argv[1]) << 20,), daemon=True).start()
        State.loop = asyncio.new_event_loop()
        asyncio.set_event_loop(State.loop)
        threading.Thread(target=read, daemon=True).start()
        State.loop.run_forever()
        """#
}
