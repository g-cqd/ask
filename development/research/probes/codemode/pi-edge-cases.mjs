import { CodemodeSandbox } from "/Users/gc/.pi/agent/install/releases/1.4.0/node_modules/@earendil-works/pi-codemode/dist/index.js";
const calls = [];
const sandbox = new CodemodeSandbox({ timeoutMs: 2000, memoryLimitBytes: 64 * 1024 * 1024, tools: [
  { name: "read", execute: async (args) => { calls.push(args); return "the note"; } },
  { name: "slow", execute: async (args, { signal }) => new Promise((resolve, reject) => { const t = setTimeout(() => resolve("slow done"), 30); signal?.addEventListener("abort", () => { clearTimeout(t); reject(new Error("aborted")); }); }) },
  { name: "fail", execute: async () => { throw new Error("no such file"); } },
] });
async function run(label, code) {
  const t = performance.now(); const r = await sandbox.execute(code); const ms = (performance.now() - t).toFixed(1);
  console.log(`${label}: ${ms} ms ok=${r.ok} value=${JSON.stringify(r.value)} error=${r.ok ? "" : r.error.kind + ": " + String(r.error.message).slice(0, 70)} output=${JSON.stringify(r.output).slice(0, 110)} calls=${r.calls.map((c) => c.status).join(",").slice(0, 60)}`);
}
await run("one call", `const a = await tools.read({path:"x"}); text("got " + a); return a.length;`);
await run("one call again", `return await tools.read({path:"y"});`);
await run("100 parallel x 30ms", `const all = await Promise.all(Array.from({length:100}, (_, i) => tools.slow({i}))); return all.length;`);
await run("failing call", `try { await tools.fail({}); } catch (e) { return "caught " + e.message; }`);
await run("uncaught", `await tools.fail({});`);
await run("unawaited call", `tools.slow({}); return 1;`);
await run("never settles", `await new Promise(() => {}); return 1;`);
await run("spin", `while (true) {}`);
await run("memory", `const big = []; for (;;) big.push(new Array(1 << 16).fill(1));`);
await run("syntax error", `return (;`);
await run("output then throw", `text("partial"); throw new Error("after output");`);
await run("exit()", `text("kept"); exit(); text("never");`);
await run("globals", `return ["fetch","require","process","setTimeout","WebAssembly","Date","Math","eval"].map(n => n + "=" + typeof globalThis[n]);`);
await sandbox.close();
