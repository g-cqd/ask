import readline from "node:readline";
import process from "node:process";
const pending = new Map(); let next = 0;
const send = (m) => process.stdout.write(JSON.stringify(m) + "\n");
const tools = new Proxy({}, { get: (_, name) => (args) => new Promise((resolve, reject) => {
  const id = ++next; pending.set(id, { resolve, reject }); send({ call: id, tool: String(name), args: args ?? null }); }) });
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;
readline.createInterface({ input: process.stdin }).on("line", async (line) => {
  const m = JSON.parse(line);
  if (m.script !== undefined) {
    try { const v = await new AsyncFunction("tools", "text", m.script)(tools, (t) => send({ text: String(t) })); send({ done: v === undefined ? null : v }); }
    catch (e) { send({ failed: String(e && e.stack || e) }); }
    process.exit(0);
  } else { const p = pending.get(m.id); pending.delete(m.id); m.error ? p.reject(new Error(m.error)) : p.resolve(m.result); }
});
send({ ready: true });
