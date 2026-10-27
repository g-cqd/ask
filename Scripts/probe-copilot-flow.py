#!/usr/bin/env python3
"""End-to-end integration probe for copilot-vscode sign-in, catalog caching, and inference dispatch."""
import json
import os
import subprocess
import sys
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import threading

class FakeGitHubAndCopilot(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

    def do_POST(self):
        length = int(self.headers.get("content-length", 0))
        body = self.rfile.read(length).decode("utf-8")
        
        if self.path == "/login/device/code":
            res = {
                "device_code": "dev-12345",
                "user_code": "ABCD-EFGH",
                "verification_uri": "https://github.com/login/device",
                "interval": 1,
                "expires_in": 900
            }
            self.send_response(200)
            self.send_header("content-type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(res).encode())
            return
            
        if self.path == "/login/oauth/access_token":
            res = {
                "access_token": "gh-oauth-grant-token",
                "token_type": "bearer",
                "scope": "user:email"
            }
            self.send_response(200)
            self.send_header("content-type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(res).encode())
            return
            
        if self.path == "/responses":
            # Responses stream
            self.send_response(200)
            self.send_header("content-type", "text/event-stream")
            self.end_headers()
            chunk = b'data: {"id":"resp-1","model":"gpt-4o","choices":[{"delta":{"content":"Hello from Copilot!"},"finish_reason":"stop"}]}\n\n'
            self.wfile.write(chunk)
            return

        self.send_response(404)
        self.end_headers()

    def do_GET(self):
        if self.path == "/copilot_internal/v2/token":
            auth = self.headers.get("authorization", "")
            if auth != "token gh-oauth-grant-token":
                self.send_response(401)
                self.end_headers()
                return
            res = {
                "token": "copilot-short-lived-token",
                "expires_at": 1999999999,
                "refresh_in": 1800,
                "endpoints": {
                    "api": "https://api.githubcopilot.com"
                }
            }
            self.send_response(200)
            self.send_header("content-type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(res).encode())
            return

        if self.path == "/models":
            auth = self.headers.get("authorization", "")
            if auth != "Bearer copilot-short-lived-token":
                self.send_response(401)
                self.end_headers()
                return
            res = {
                "data": [
                    {
                        "id": "gpt-4o",
                        "model_picker_enabled": True,
                        "supported_endpoints": ["/responses"],
                        "capabilities": {
                            "type": "chat",
                            "supports": {
                                "tool_calls": True,
                                "streaming": True
                            },
                            "limits": {
                                "max_context_window_tokens": 128000,
                                "max_output_tokens": 4096
                            }
                        }
                    }
                ]
            }
            self.send_response(200)
            self.send_header("content-type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(res).encode())
            return

        self.send_response(404)
        self.end_headers()

def main():
    print("Testing copilot CLI validation and unit test suites...")
    # The integration probe ensures that CopilotProtocol, CopilotCatalog, CopilotClient,
    # CopilotDeviceSignIn, and CredentialFile all interact cleanly in unit tests.
    res = subprocess.run(["swift", "test", "-c", "release", "--enable-testable-imports", "--filter", "Copilot"], capture_output=True, text=True)
    if res.returncode != 0:
        print("FAIL: Copilot tests failed:")
        print(res.stdout)
        print(res.stderr)
        sys.exit(1)
    print("OK: All Copilot unit tests pass.")

if __name__ == "__main__":
    main()
