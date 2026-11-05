---
status: in-progress
blocked-by: []
date: 2026-10-29
---

# 0139 — AemiHTML, promoted from the archived ADHTML, if something needs to parse HTML

Owner wish (2026-10-29 04:53): "HTML parsing is deeply suboptimal, the archived AD* family has ADHTML, with work for an high performance HTML parser, we
should promote it and modernize it to our most up to date standards into AemiHTML and reuse it relevantly in AemiMarkdown. -- only necessary if
AemiMarkdown needs HTML parsing".

## Assessment (2026-10-29)

**AemiMarkdown does not need HTML parsing.** CommonMark and GFM never build an HTML tree: an HTML block is recognised by seven start and end conditions,
and inline HTML by a regular grammar (CommonMark 4.6 and 6.6). AemiMarkdown does both with byte scanners, checked against the spec's own grammars
compiled by AemiRegex (its default suite) and against cmark 0.31.2 (no difference on HTML in 25,000 random inputs). Measured, release build, same machine:
Markdown dense with inline HTML parses at 238 to 243 MB/s and with HTML blocks at 253 to 268 MB/s, against 446 to 454 MB/s for prose of the same size;
the HTML files make three times as many nodes (204,914 against 64,638), so the cost per node is about the same. Not suboptimal on this evidence.

**ask does not parse HTML anywhere today** (no fetch tool; the only HTML is the sign-in page it serves).

**What ADHTML has** (`g-cqd/ADHTML`, archived 2026-10-22): mostly a server-side rendering engine (reactive views, hydration, a client runtime, macros),
which has no use here, and in `ADHTMLCore/Parse` a tokenizer, a tree builder and an HTML-to-Markdown and plain-text extractor ported from a crawler
(about 2,000 lines), plus a 669-line tokenizer kept as an oracle.

## When it would be worth building

A tool that fetches web pages for the model (a `fetch` or `web` tool) would need exactly that extractor: page in, Markdown out, chrome dropped,
in a bounded, non-recursive parser. That is the consumer to wait for. Then: extract `Parse/` into AemiHTML with the family's standards (no recursion,
the `HTMLNode` walk is recursive today; tapes rather than a class tree; allocation ceilings; html5lib tokenizer tests; Aemi pin), and measure against a
baseline before claiming anything.

## Closed by the owner (2026-10-29)

No implementation: the condition is not met. AemiMarkdown does not need HTML parsing. Reopen only for a concrete HTML-consuming feature.

## Reopened by the owner (2026-11-05)

"Look at adhtml somewhere in g-cqd repos, and maybe we can promote that to aemihtml, and rebuild it on our high performance tooling." The condition above (a consumer) is waived by that request; the extractor is still the consumer to build towards.

- **ADHTML's source was found** (an earlier line here said it could not be: wrong). It is on the owner's other machine, a git checkout of 195 commits whose last one archives the repository. Read there, it was a pragmatic subset: a tape tokenizer without the RCDATA, RAWTEXT and script states, a tree builder
  without insertion modes, adoption agency or tables, a recursive `indirect enum` DOM cut at depth 128, and recursive extractors that flattened nested lists, lost tables and code languages, did not escape text, and kept hidden text. AemiHTML therefore **rebuilds** it, keeping its API contract (title,
  description, container, sections at `h2`, Markdown or plain text, link resolver, chrome stripping), and `AemiHTML/docs/adr/0001-…` says what was kept and what changed.
- **Built (`g-cqd/AemiHTML`, local, not pushed):** the WHATWG tokenizer and tree builder on Aemi's kernels and flat arrays (no object per token or node; counted by allocation tests), the arena document, iterative walks, and the extractors. Checked against html5lib's tokenizer tests (about 7,000 cases),
  its tree-construction tests (1,792 cases, eight known differences each with its reason), hostile and fuzz documents, and html5ever: identical token streams on 15 real pages (about 1.4 million tokens). Tokenizing is about 1.8 to 2 times html5ever's speed, parsing to a DOM about 1.6 times Lexbor's (ratios; the machine was loaded).
  Extraction of the 15 pages takes 0.2 s. Extracted Markdown is read back with AemiMarkdown in tests.
- **Built since (2026-11-05, later):** the Encoding Standard (sniffing, the late-`meta` restart, every decoder), `HTMLStreamParser` (the tree of the whole document at every cut), `selectedcontent`, input decoded as UTF-8 is decoded. **Left, in `AemiHTML/docs/roadmap.md` and `docs/design/remaining-work.md`:** the tree builder's own parse errors (needs a decision), the builder's cost (about 1,900 instructions per node), web-platform-tests' tree files, and the `fetch` tool in ask that would use `HTMLExtractor` (the owner said not to care about it for now).
- Research notes that bear on it: `g-cqd/research`, topics 01, 11, 12.
