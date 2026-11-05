---
status: reopened
blocked-by: ["a consumer that parses HTML"]
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

- **ADHTML's source could not be recovered**: `g-cqd/ADHTML` does not resolve on GitHub and no checkout exists on this machine (only archived design records in a Copilot cache). AemiHTML is therefore a new build to this roadmap's description, not a port.
- **Built (`g-cqd/AemiHTML`, local, not pushed):** a WHATWG tokenizer on Aemi's kernels (SIMD byte-set scans, a `TapeSlot` token tape, no object per token), checked against html5lib's tokenizer tests (about 7,000 cases, tokens and error codes, including the processing-instruction
  states added to the standard in 2026), and benchmarked against html5ever (126.7 against 80.7 MB/s with errors off; level with it, 77.9 against 80.7, with errors collected) and Python's `html.parser` on 15 real pages.
- **Next, in `AemiHTML/docs/roadmap.md`:** tree construction (tests now live in web-platform-tests), the HTML-to-text and Markdown extractors, streaming, encoding sniffing.
- Research notes that bear on it: `g-cqd/research`, topics 01, 11, 12.
