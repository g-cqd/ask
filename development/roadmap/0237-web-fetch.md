---
status: not-started
blocked-by: []
date: 2026-11-13
---

# 0237 — Web fetch: a page read as Markdown, marked untrusted

From the study of other agents (proposal 6), chosen 2026-11-13, a cheap one done first.

A `fetch` tool: a URL read (HTTPS, redirects followed within the same rules, a size limit), HTML turned into Markdown with
AemiHTML, other text as text, under the approvals (a host allowed once, always or never). The page's text is marked as untrusted in
the context (the policy of the security entry). Search through a configured provider is a later step.

## Done when

A probe fetches a local page into Markdown; an approval is asked for a new host; a page's instructions do not run anything.
