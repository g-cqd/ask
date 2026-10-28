// Runs pi's own compaction context builder on nested compactions (ask ADR-0012).
//   PI_VERSION=1.4.0 node development/research/probe-pi-compaction-context.mjs
import os from "node:os";
const version = process.env.PI_VERSION ?? "1.3.0";
const dist = `${os.homedir()}/.pi/agent/install/releases/${version}/node_modules/@earendil-works/pi-coding-agent/dist`;
const { buildContextEntries, buildSessionContext } = await import(`${dist}/core/session-manager.js`);
console.log(`pi ${version}`);

const at = "2026-10-18T00:00:00Z";
const msg = (id, parentId, text) => ({
  type: "message", id, parentId, timestamp: at,
  message: { role: "user", content: [{ type: "text", text }], timestamp: 0 },
});
const compaction = (id, parentId, firstKeptEntryId, summary) => ({
  type: "compaction", id, parentId, timestamp: at, summary, firstKeptEntryId, tokensBefore: 1000,
});

// The newest compaction keeps from `root`, so the range it retains contains the older compaction.
const entries = [
  msg("root", null, "root"),
  compaction("c1", "root", "root", "OLDER SUMMARY"),
  msg("middle", "c1", "middle"),
  compaction("c2", "middle", "root", "LATEST SUMMARY"),
];
console.log("context entry ids:", JSON.stringify(buildContextEntries(entries, "c2").map((e) => e.id)));

const messages = buildSessionContext(entries, "c2").messages;
const text = JSON.stringify(messages);
console.log("summaries in model context:",
  ["OLDER SUMMARY", "LATEST SUMMARY"].filter((s) => text.includes(s)).join(", "));

// A compaction whose firstKeptEntryId is on another branch (hand edit or damage).
const offBranch = [
  msg("root", null, "root"),
  msg("other", "root", "other"),
  msg("x", "root", "x"),
  compaction("c", "x", "other", "SUMMARY"),
  msg("after", "c", "after"),
];
console.log("boundary off branch -> context entry ids:", JSON.stringify(buildContextEntries(offBranch, "after").map((e) => e.id)));
