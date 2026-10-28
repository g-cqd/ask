// A fake streamable-HTTP MCP server for MCPStress, on Node or Bun. Usage: http_server.mjs PORT json|sse
import { createServer } from "node:http";

const port = Number(process.argv[2] ?? 8765);
const mode = process.argv[3] ?? "json";
const replies = new Map();

function result(message) {
  switch (message.method) {
    case "initialize":
      return { protocolVersion: message.params.protocolVersion, capabilities: { tools: {} },
               serverInfo: { name: "fake-http", version: "1" } };
    case "tools/call": {
      const size = message.params.arguments.size ?? 2;
      if (!replies.has(size)) replies.set(size, { content: [{ type: "text", text: "x".repeat(size) }], isError: false });
      return replies.get(size);
    }
    default:
      return {};
  }
}

createServer((request, response) => {
  if (request.method === "DELETE") { response.writeHead(200); response.end(); return; }
  if (request.method !== "POST") { response.writeHead(405); response.end(); return; }
  const chunks = [];
  request.on("data", (chunk) => chunks.push(chunk));
  request.on("end", () => {
    const message = JSON.parse(Buffer.concat(chunks).toString("utf8"));
    if (message.id === undefined) { response.writeHead(202); response.end(); return; }
    const body = JSON.stringify({ jsonrpc: "2.0", id: message.id, result: result(message) });
    if (mode === "sse") {
      response.writeHead(200, { "content-type": "text/event-stream", "mcp-session-id": "s1" });
      response.end(`event: message\ndata: ${body}\n\n`);
    } else {
      response.writeHead(200, { "content-type": "application/json", "mcp-session-id": "s1" });
      response.end(body);
    }
  });
}).listen(port, "127.0.0.1", () => process.stdout.write(`listening ${port}\n`));
