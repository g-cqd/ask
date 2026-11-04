#!/usr/bin/env python3
"""An MCP server behind OAuth for ask's sign-in probe (roadmap 0067): streamable HTTP on 127.0.0.1, refusing without a token with a
401 that names its protected resource metadata, and its own authorization server (RFC 8414 metadata, dynamic registration, an
authorization endpoint that approves at once, a token endpoint that checks PKCE and the resource indicator).

python3 oauth-server.py PORT_FILE    writes the port it took to PORT_FILE, then serves until killed.
"""
import base64, hashlib, json, sys, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

codes = {}
TOKEN = "good-token"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def base(self):
        return f"http://127.0.0.1:{self.server.server_address[1]}"

    def reply(self, status, body=b"", headers=None, kind="application/json"):
        self.send_response(status)
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        if body:
            self.send_header("content-type", kind)
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def json(self, value, status=200):
        self.reply(status, json.dumps(value).encode())

    def do_GET(self):
        url = urllib.parse.urlparse(self.path)
        if url.path == "/.well-known/oauth-protected-resource/mcp":
            return self.json({"resource": self.base() + "/mcp", "authorization_servers": [self.base()]})
        if url.path == "/.well-known/oauth-authorization-server":
            return self.json({"issuer": self.base(), "authorization_endpoint": self.base() + "/authorize",
                              "token_endpoint": self.base() + "/token", "registration_endpoint": self.base() + "/register",
                              "code_challenge_methods_supported": ["S256"]})
        if url.path == "/authorize":
            query = dict(urllib.parse.parse_qsl(url.query))
            if query.get("resource") != self.base() + "/mcp" or query.get("code_challenge_method") != "S256":
                return self.reply(400, b"bad request")
            code = "code-" + str(len(codes) + 1)
            codes[code] = query["code_challenge"]
            target = query["redirect_uri"] + "?" + urllib.parse.urlencode({"code": code, "state": query["state"]})
            return self.reply(302, headers={"location": target})
        self.reply(405)

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("content-length", 0)))
        url = urllib.parse.urlparse(self.path)
        if url.path == "/register":
            return self.json({"client_id": "client-1"}, 201)
        if url.path == "/token":
            form = dict(urllib.parse.parse_qsl(body.decode()))
            verifier = form.get("code_verifier", "")
            challenge = base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).rstrip(b"=").decode()
            if codes.get(form.get("code")) != challenge or form.get("resource") != self.base() + "/mcp":
                return self.json({"error": "invalid_grant"}, 400)
            return self.json({"access_token": TOKEN, "token_type": "Bearer", "expires_in": 3600, "refresh_token": "refresh-1"})
        if url.path != "/mcp":
            return self.reply(404)
        if self.headers.get("authorization") != "Bearer " + TOKEN:
            metadata = self.base() + "/.well-known/oauth-protected-resource/mcp"
            return self.reply(401, headers={"www-authenticate": f'Bearer resource_metadata="{metadata}"'})
        message = json.loads(body)
        ident, method = message.get("id"), message.get("method")
        if ident is None:
            return self.reply(202)
        if method == "initialize":
            result = {"protocolVersion": message["params"]["protocolVersion"], "capabilities": {"tools": {}},
                      "serverInfo": {"name": "oauth-fixture", "version": "1"}}
        elif method == "tools/list":
            result = {"tools": [{"name": "whoami", "description": "who is signed in", "inputSchema": {"type": "object"}}]}
        else:
            result = {}
        self.json({"jsonrpc": "2.0", "id": ident, "result": result})


server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
with open(sys.argv[1], "w") as file:
    file.write(str(server.server_address[1]))
server.serve_forever()
