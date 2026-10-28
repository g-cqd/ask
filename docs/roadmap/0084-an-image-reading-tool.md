---
status: done
blocked-by: []
date: 2026-10-28
---

# 0084 — An image reading tool

Owner request, from `ask-wishes.md`, marked a priority: the model can read an image file.

Originally `ReadTool` read text only and no image reached a model. It is now done end to end (see Progress); the sections
below record what was learned from other harnesses and what was built.

## What other harnesses do (read 2026-10-28)

pi (installed package), opencode (`dev`), Codex (`codex-rs`), gemini-cli and VS Code Copilot Chat 0.44.0, all read as source, none
run except through Copilot. Claude Code is not available as source and was not read.

| Question | pi | opencode | Codex | gemini-cli | VS Code Copilot |
| --- | --- | --- | --- | --- | --- |
| Tool | `read` handles text and images | `read` handles images and PDF | `view_image`, offered only when the model's `input_modalities` has image | `read_file` returns `inlineData` for image, PDF and video (20 MB cap) | read tool; attachments |
| Sizing | 2000 px, 4.5 MiB, JPEG qualities 80..40 | refuses above 20 MiB, no resize | 2048 px / 2,500 patches of 32 px; "original" 6000 px; LRU cache by SHA-1 | none | none (no resize) |
| Model cannot see images | note in the tool text | text placeholder from declared modalities | images stripped before the request, placeholder text; MCP images replaced too | n/a (Gemini models see) | by catalogue `supports.vision` |
| Total budget | one image per read | oldest replaced past 25 MiB, down to 15 | n/a | n/a | count checked for Gemini only; catalogue `limits.vision` |
| Context cost | not estimated | not estimated | fixed 7,373 bytes per image (about 1.8k tokens) | fixed 3,000 tokens per image, a PDF about 25,800 | n/a |
| Wire | Anthropic block; OpenAI chat: text + follow-up user message; Gemini 3 nested, older Gemini separate turn | neutral file part | Responses `input_image` | Gemini 3 (`gemini-3-`) nests `inlineData` in `functionResponse.parts`, other models siblings after it | uploads to a closed attachment endpoint on chat/Messages, base64 fallback |

## What this means for ask, and what was done

- One tool, bytes sniffed: `read` (done). Provider-neutral `ImagePart` (done), encoded per wire (done, below).
- Sizing: ask follows pi (2000 px, 4.5 MiB, qualities) and further bounds by the provider's own limits (`ImageReader.Allowance`).
- Capability: decided from a declared or catalogue value (`acceptsImages`), as Codex and opencode do; unknown withholds with a reason.
- Budget: `ImagePart.filtering` caps the count per request, dropping the oldest down to half (opencode's stepwise idea, kept
  cache-friendly). The default of 20 where a provider says nothing is a guess.
- Context cost: a fixed 12,000 bytes (3,000 tokens) per image in `Compaction.size`, gemini-cli's number. Measured through Copilot: a
  64x64 image adds under 100 tokens, a 2000x1500 one about 3.6k (GPT) to 3.9k (Claude). Never the base64 length.
- Wires: Anthropic inside the tool result; OpenAI chat and Responses a follow-up user message (`detail: "auto"`); Agy and Gemini
  follow gemini-cli: nested in `functionResponse.parts` for `gemini-3*`, sibling `inlineData` parts after the responses otherwise;
  Apple stays text.
- MCP image results use the same path (`MCPResultImages`): sniffed, decoded, bounded, at most 8 per result, never trusted by declared type.
- Persistence: pictures are files beside the session (`images/<sha256>`, 0600), referenced from the record. Needed for
  correctness too: the log's line limit is 1 MiB, so an inline 4 MB picture would have cost the whole record on resume.
- PDFs: text for pages that have a text layer, pictures for pages that do not, `render: true` for pictures of every page.

## Decision: PDF as text, not as a native document

Measured with a 31-page text PDF (90 KB of text): PDFKit extracted it in 119 ms the first time in a process, about 2.9 KB a page
(roughly 750 tokens), against 1.5k to 3.9k tokens for a rendered page. A native `document` block (Anthropic), `input_file`
(Responses) or PDF `inlineData` (Gemini) makes the provider read both the text and an image of each page, so it costs at least as
much as pictures, is unavailable to text-only models, and needs three new wire shapes. Text is cheaper, exact, and works on every
provider and for models without images. Scans and drawings still go as pictures. Native PDF upload stays unbuilt, and unprobed.
Linking PDFKit cost about 0.16 MiB RSS and under 1 ms in a minimal program (the shared cache holds it).

## Progress (2026-10-28)

- Done and pushed earlier: value type, sniff/bound/downscale, PDF/video/formats, sandbox-verified reads, filtering and capability,
  OpenAI/Anthropic encoders, Copilot limits and VS Code header parity (`df19552`, `8df567d`, `14188a5`).
- Done in the final slice (diary 2026-10-28-08): Agy/Gemini images, MCP images, context cost per image, persistence by hash,
  PDF text, and this review.
- Live checks with an unguessable test image (orange left, purple right, white diagonal): Agy `gemini-3-flash`,
  `gemini-3.8-flash-medium`, `claude-sonnet-5-5-low` correct both nested and sibling; `gemini-3.5-flash-lite` correct as siblings;
  Copilot `claude-haiku-5.5` and `kimi-k3` correct, `gpt-6-luna` saw the colours and the diagonal but misplaced the layout.
- Not verified: `gemini-4-*` on Agy (quota, 429 for 59 h); `gpt-oss` is judged text-only by name, never sent an image; the OpenAI
  direct API, Anthropic direct and Apple wires with a live image; Copilot header necessity, over-limit behaviour, raw-vs-base64 byte
  limit and accounting; the 20-image default; the end-to-end `AgentLoop.request` filter wiring has no test of its own; a real
  photograph and a scanned PDF; native PDF upload. Images are macOS only. Audio and WebM/MKV are not handled.
- Separate bug found, not fixed here: `gemini-2.5-flash` on Agy refuses any tool call (HTTP 400, missing `thought_signature`),
  with or without images. Tracked in 0069.
