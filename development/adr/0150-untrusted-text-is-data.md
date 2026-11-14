---
status: accepted
date: 2026-11-13
---

# 0150 — Text from outside is data: said so where it enters, unable to leave its section, and never a cause by itself

## Context

A coding agent reads text nobody on the machine wrote: web pages, issues, a server's resources, files of a repository, a command's
output. Such text can be written to steer the model (prompt injection). The owner asked for safeguards (note n33); security audit 3
(`development/research/security-audit-2026-11-13.md`) found the places where ask itself gave such text more than it should: an
issue's body and a server's resource sat in the person's own message with nothing saying whose words they were and could end their
section; a page could close the markers `fetch` put around it; the goal's judge passed on what it concluded from the run as an
instruction.

## Decision

1. **What is untrusted.** Anything the person did not type and ask did not write: a page, a pull request or issue, a server's
   resource or tool result, a file's content, a command's output, and what another model concludes from any of these.
2. **Said where it enters.** When ask puts such text into the person's message (`#123`, `@server:uri`) or composes a tool result
   around it (`fetch`), it starts with `UntrustedText.notice`: where it is from, that it is data, not instructions.
3. **Unable to leave its section.** The text cannot close the section it is in nor open another: a line that starts as an
   attachment marker does is given a backslash (`UntrustedText.insideAttachment`), and a tagged section never holds its own tag
   (`insideTags`). Fields that are one line (a title, an author) are made one line.
4. **Tool results are not wrapped.** A command's output, a file read and an MCP tool's result arrive in the tool-result role, which
   is data by the protocol; a wrapper on each would cost tokens and add nothing to the role.
5. **Never a cause by itself.** What changes things goes through the approvals whatever the model was told: a command, a file
   written or edited, an address fetched (the address can carry data out; the grant is the host), an app or a command opened by a
   click (ADR-0148), an MCP tool that is not read-only. A standing grant is the person's choice and theirs to bound.
6. **What ask does unasked is safe in a hostile folder.** Before any approval ask reads the workspace: its git state through
   `GitQuery` (nothing the repository's configuration names runs), its project configuration and skills only once trusted by digest.
7. **A model that reads the run is told so, and speaks for itself.** The goal's judge is told that the run's text decides nothing;
   what it answers reaches the working model as the judge's words, never as the person's.

## Consequences

- These rules bound what persuasion can cause without the person; they do not make a model deaf to what it reads. A model
  persuaded by a page still has to ask before anything changes.
- A new way for outside text to enter the person's message or a composed result uses `UntrustedText`; a test per entry holds the
  rule (`FetchToolTests`, `ForgeReferencesTests`, `ResourceReferencesTests`, `UntrustedTextTests`, `GoalTests`).
- Tasks, notes and thread summaries attached with `#t3` are the session's own; they are not marked.
