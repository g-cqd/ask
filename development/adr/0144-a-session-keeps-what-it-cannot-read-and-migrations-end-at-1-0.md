---
status: accepted
date: 2026-11-04
---

# 0144 — A session file keeps what it cannot read, and its migrations are removed before 1.0

Extends ADR-0017 (append-only session files) and ADR-0138 (the framed container). Roadmap 0195 needs new facts in a session: threads
started, renamed and merged.

## Context

Today an ask that meets a session line it does not know treats it as damage:

- An unknown record `type`, or an unknown entry `kind`, is reported as a malformed line (`SessionLogRecovery`).
- The file then gets a `.damaged` copy when the session next changes.
- An entry whose parent was that line is re-rooted, which cuts the conversation in two.
- A newer `formatVersion` is refused outright (`unsupportedVersion`).
- A repair or a format upgrade rewrites the file from the tree in memory (`SessionFile.rewrite`), so anything not in the tree is lost.

Adding thread facts would therefore mean either raising the format version, which a session from an older ask can no longer cross, or
having those facts read as damage. The owner chose (2026-11-04): ignore unknown entries, and convert older files with migration steps
that are removed once ask reaches release candidate 1.0.

## Decision

- **Facts about a session, rather than turns of its conversation, are records.** Threads started, renamed and merged are records of
  `type: "thread"`, beside `leaf` and `sandbox`, and outside the conversation tree.
- **A record of an unknown type is kept, not read.** It is not an issue and not damage. Its line is kept byte for byte, in the order
  it came, and a rewrite writes it back.
- **An entry of an unknown kind is kept, not read.** It becomes `SessionPayload.unrecognized(kind:fields:)`, the way
  `ContentBlock.unrecognized` already keeps a block type ask does not know. It stays in the tree, so its children still hang from it.
  It adds nothing to a request's context, nothing is shown for it, and it is written back as it was.
- **A known type or kind that is wrong is still damage,** repaired as before: a missing field, the wrong type, a bad identifier.
  "Unknown" means only a type or kind name this build does not have.
- **`formatVersion` stays 2** while additions can be made this way. It is raised only when an older ask would misread a file, not
  merely fail to understand part of it.
- **Migrations.** A migration is an ordered step that converts an older file's lines on opening, and is named after what it converts
  (`SessionMigration`, in `Sources/AskAgentCore/Session/Migrations/`). The existing upgrade from format 1 becomes the first of them.
  Each step:
  - is applied in memory;
  - says once that it was applied;
  - is written on the next change, keeping the original as `.version-N`, as upgrades do today;
  - may be applied again without changing anything.
- **Migrations end before 1.0.** Every step is marked `removeBefore: "1.0.0-rc.1"`. Roadmap 0070 (a version and a release) lists
  removing them, and the format they leave becomes 1.0's baseline. A test fails if a step exists without that mark, so a step cannot
  be added and forgotten.

## Consequences

- Sessions written by a newer ask open in an older ask (from this one on) with nothing lost and nothing reported. Sessions written by
  asks before this change still read new records as damage. That is accepted before 1.0.
- A file is no longer proven whole just by decoding every line. A record or entry that is truly corrupt but carries a
  plausible-looking unknown name is now kept rather than reported. Integrity still rests on the framing and the checks of ADR-0138.
- Tests:
  - an unknown record and an unknown entry, with a child under it, survive a resume and a rewrite byte for byte, and raise no issue;
  - the context and the screen ignore both;
  - a known kind with a bad field is still repaired;
  - the format-1 migration passes through the new step list;
  - every step is marked for removal.
