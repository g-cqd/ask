#!/usr/bin/env python3
"""A loopback web server for the probes' background jobs: `python3 -u Scripts/serve-loopback.py PORT`.

Not `python3 -m http.server`: that one asks for the machine's own name before it listens (`HTTPServer.server_bind` calls
`socket.getfqdn`), which took 35 s on CI's runner, with or without ask (2026-11-17), where a probe waits 20 s for the port.
A file and not `python3 -c`: the probes read the command back from a row of the screen, where a long one is cut.
"""
import http.server
import socketserver
import sys

port = int(sys.argv[1])
socketserver.TCPServer.allow_reuse_address = True
server = socketserver.TCPServer(("127.0.0.1", port), http.server.SimpleHTTPRequestHandler)
print(f"Serving HTTP on 127.0.0.1 port {port}", flush=True)
server.serve_forever()
