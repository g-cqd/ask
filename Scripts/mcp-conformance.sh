#!/usr/bin/env bash
# The official MCP conformance suite's client scenarios against AskMCP (roadmap 0123, step 1).
# Usage: Scripts/mcp-conformance.sh [--scenario NAME | --suite all]   (needs node's npx; results in /tmp/ask-mcp-conformance)
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
(cd "$root/Conformance" && swift build -c release --product mcp-conformance-client >/dev/null)
client="$(cd "$root/Conformance" && swift build -c release --show-bin-path)/mcp-conformance-client"
mkdir -p /tmp/ask-mcp-conformance
cd /tmp/ask-mcp-conformance
if [ "$#" -eq 0 ]; then set -- --suite all; fi
npx -y @modelcontextprotocol/conformance@0.1 client --command "$client" --expected-failures "$root/Conformance/expected-failures.yml" "$@"
