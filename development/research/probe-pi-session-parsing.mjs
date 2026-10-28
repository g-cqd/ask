// Runs pi's own exported session functions against damaged inputs (ask ADR-0012).
// Re-run against a new pi release before relying on a divergence still being one:
//   PI_VERSION=1.4.0 node development/research/probe-pi-session-parsing.mjs
import os from "node:os";
const version = process.env.PI_VERSION ?? "1.3.0";
const dist = `${os.homedir()}/.pi/agent/install/releases/${version}/node_modules/@earendil-works/pi-coding-agent/dist`;
const { parseSessionEntries, buildContextEntries } = await import(`${dist}/core/session-manager.js`);
console.log(`pi ${version}`);

const msg = (id, parentId, text) => ({
  type: "message", id, parentId, timestamp: "2026-10-18T00:00:00Z",
  message: { role: "user", content: [{ type: "text", text }], timestamp: 0 },
});
const header = JSON.stringify({ type: "session", version: 3, id: "s", timestamp: "x", cwd: "/" });
const a = JSON.stringify(msg("a", null, "first"));
const b = JSON.stringify(msg("b", "a", "second"));
const c = JSON.stringify(msg("c", "b", "third"));

const report = (name, value) => console.log(`${name}: ${JSON.stringify(value)}`);

// 1. Crash mid-write: final record cut off, no trailing newline.
const torn = [header, a, b, c.slice(0, c.length - 7)].join("\n");
report("torn final line -> parsed ids", parseSessionEntries(torn).filter(e => e.id).map(e => e.id));

// 2. Corruption in the middle of the file.
const corrupt = [header, a, "{not json", c].join("\n") + "\n";
report("corrupt middle line -> parsed ids", parseSessionEntries(corrupt).filter(e => e.id).map(e => e.id));

// 3. A leaf id that does not exist.
const entries = [msg("a", null, "first"), msg("b", "a", "second")];
report("unknown leaf -> context ids", buildContextEntries(entries, "ghost").map(e => e.id));

// 4. A parent that does not exist: the walk just ends.
const orphaned = [msg("a", null, "first"), msg("c", "missing", "orphan")];
report("missing parent -> context ids", buildContextEntries(orphaned, "c").map(e => e.id));
