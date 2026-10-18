// Runs pi's own file loader on damaged session files in a temp directory (ask ADR-0012).
//   PI_VERSION=1.4.0 node Scripts/probe-pi-session-loading.mjs
import { mkdtempSync, writeFileSync, readFileSync, rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";
const version = process.env.PI_VERSION ?? "1.3.0";
const dist = `${os.homedir()}/.pi/agent/install/releases/${version}/node_modules/@earendil-works/pi-coding-agent/dist`;
const { loadEntriesFromFile, buildContextEntries } = await import(`${dist}/core/session-manager.js`);
console.log(`pi ${version}`);

const dir = mkdtempSync(path.join(os.tmpdir(), "pi-probe-"));
const at = "2026-10-18T00:00:00Z";
const header = JSON.stringify({ type: "session", version: 3, id: "s", timestamp: at, cwd: "/" });
const msg = (id, parentId, text) => JSON.stringify({
  type: "message", id, parentId, timestamp: at,
  message: { role: "user", content: [{ type: "text", text }], timestamp: 0 },
});
const load = (name, content) => {
  const file = path.join(dir, name);
  writeFileSync(file, content);
  const ids = loadEntriesFromFile(file).map((e) => e.id);
  return { ids, changedOnDisk: readFileSync(file, "utf8") !== content, after: readFileSync(file, "utf8") };
};

// 1. The header line is corrupt; every message after it is intact.
const noHeader = load("no-header.jsonl", ["{corrupt header", msg("a", null, "x"), msg("b", "a", "y")].join("\n") + "\n");
console.log("corrupt header -> loaded ids:", JSON.stringify(noHeader.ids));

// 2. The final record is torn by a crash. Does loading modify the file?
const tornText = [header, msg("a", null, "x"), msg("b", "a", "y").slice(0, 20)].join("\n");
const torn = load("torn.jsonl", tornText);
console.log("torn tail -> loaded ids:", JSON.stringify(torn.ids), "file modified by load:", torn.changedOnDisk);
console.log("torn tail -> file now ends with:", JSON.stringify(torn.after.slice(-24)));

// 3. Two entries share an id: which one does context use?
const duplicate = [JSON.parse(msg("a", null, "first")), JSON.parse(msg("a", null, "second"))];
const chosen = buildContextEntries(duplicate, "a").map((e) => e.message.content[0].text);
console.log("duplicate id -> context text:", JSON.stringify(chosen));

rmSync(dir, { recursive: true, force: true });
