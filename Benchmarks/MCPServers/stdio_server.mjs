// A fake MCP server on standard input and output, for MCPStress; runs on Node, Bun and Deno.
import { createInterface } from "node:readline";

const replies = new Map();

function result(message) {
  switch (message.method) {
    case "initialize":
      return { protocolVersion: message.params.protocolVersion, capabilities: { tools: {} },
               serverInfo: { name: "fake-js", version: "1" } };
    case "tools/list":
      return { tools: [{ name: "echo", description: "Echo", inputSchema: { type: "object" } }] };
    case "tools/call": {
      const size = message.params.arguments.size ?? 2;
      if (!replies.has(size)) replies.set(size, { content: [{ type: "text", text: "x".repeat(size) }], isError: false });
      return replies.get(size);
    }
    default:
      return {};
  }
}

const lines = createInterface({ input: process.stdin, crlfDelay: Infinity });
lines.on("line", (line) => {
  const message = JSON.parse(line);
  if (message.id === undefined) return;
  process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id: message.id, result: result(message) }) + "\n");
});
