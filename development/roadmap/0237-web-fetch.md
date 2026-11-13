---
status: done
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

## Done (2026-11-13)

`FetchTool` (AskTools): `https` (and `http` to localhost), no credentials, no private or link-local literals; redirects followed on
the same host and checked again, to another host refused with its address; AemiHTML's extractor (now public) for HTML, text as text,
other types refused; 5 MB read, 60,000 characters returned; the page between `<untrusted-web-content>` markers, said to be data. It
asks by default, and an approval covers its host for the session (`CallScope.host`, kept across `/reload`). Search is not in it.
