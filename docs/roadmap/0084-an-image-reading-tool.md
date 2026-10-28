---
status: in-progress
blocked-by: []
date: 2026-10-28
---

# 0084 — An image reading tool

Owner request, from `ask-wishes.md`, marked a priority: the model can read an image file.

Today `ReadTool` reads text. `RequestBlock.toolResult` carries a `String`, and an MCP image result is replaced by a
line such as "[image image/png, N bytes: ask cannot show it]" (`MCPResultText`), so no image reaches a model. ask has no
model input-modality field (only the Codex catalog decodes `input_modalities`).

## What other harnesses do (read 2026-10-28)

Read from pi's installed package (`@earendil-works/pi-coding-agent`, `pi-ai`, `pi-tui`) and from opencode's source
(`anomalyco/opencode`, `dev` branch: `packages/core/src/tool/read-filesystem.ts`, `session/model-request.ts`).
Not run; read only.

| Question | pi | opencode |
| --- | --- | --- |
| Tool shape | The one `read` tool: "Supports text files and images (jpg, png, gif, webp, bmp)". | The one `read` tool; media types are png, jpeg, gif, webp and PDF. |
| Detection | Sniffs the first bytes of the file (magic numbers), not the extension. Animated PNG is refused. | Sniffs the bytes (`Mime.detect`), not the extension. |
| Size | Resizes to at most 2000×2000 and 4.5 MiB encoded, trying lower JPEG quality (80, 85, 70, 55, 40); omits the image with a message if it cannot fit. Runs in a worker thread so the UI does not stall. Converts other formats (BMP) to PNG. | Refuses above 20 MiB (`MediaIngestLimitError`). No resize at read time. |
| In the conversation | An `image` content block next to the text in the tool result, plus a text note ("Read image file [image/png]", resize hint). Tool results from extensions and MCP are normalized the same way as they enter history, because one oversized image makes the provider reject every later request. | A `file` part in the tool result. |
| Total budget | One image at a time. A `blockImages` setting drops images from every request. | Replays the images in order and replaces the oldest with a placeholder once the kept images pass 25 MiB, down to 15 MiB. The cut moves only in steps, so the provider's prompt cache stays valid between cuts. |
| Model cannot see images | A note in the tool text: "Current model does not support images. The image will be omitted from this request." | Before sending, media is replaced by "ERROR: Cannot read … (this model does not support image input). Inform the user." Decided from the model's declared input modalities. |
| Provider encoding | Anthropic: image block in the tool result. OpenAI chat: tool text "(see attached image)" and then an extra user message "Attached image(s) from tool result:" with `image_url` data URLs, because that API's tool results are text only. Gemini 3+: image parts inside the function response; older Gemini: a separate user turn. | One provider-neutral media part, shaped per protocol by its `ai` package. |
| Terminal display | `pi-tui` detects the terminal and draws the image with the Kitty graphics protocol or iTerm2 inline images; none under tmux, where it shows text. | Desktop and web UI show an attachment card; the terminal UI shows the attachment as text. |

## What this means for ask

- Follow the one-tool shape: extend `read` rather than add an `image` tool. The model already knows `read`, and
  both harnesses do it. Sniff the bytes, as both do.
- ask needs a provider-neutral image part first (`RequestBlock` and the tool result), then a per-provider encoding
  that includes the OpenAI chat workaround (a follow-up user message) and Gemini's older-model rule.
- Resizing is the part pi spends the most code on, and the part ask can least afford to skip: an unbounded image
  makes the provider reject the entire conversation, not only that turn. ImageIO and CoreGraphics on macOS can
  decode, scale and re-encode without a dependency; check that this also holds on Linux or limit images to macOS.
- A per-request image budget with oldest-first replacement (opencode's approach, in steps for the prompt cache) is
  worth taking, even if the first version has one image per read and a fixed cap.
- A model that cannot take images must get a clear text result, decided from a declared modality. ask needs that
  field in its model catalogs (Codex has it; the others need a default and an override).
- Showing the pixels in the terminal (Kitty or iTerm2 protocol, off under tmux) is optional and separate. The
  first version shows a one-line block: type, dimensions, size.

## Still owed

- Write the design from the section above: the content part, the encoding per provider, the limits (type list,
  maximum encoded size, maximum dimension), the cap on images per request, the modality field.
- Session persistence: store the image by reference or as size-capped data, so a resumed session stays small;
  check what an image adds to the context estimate.
- The MCP image result then uses the same part (today it is only described in text).
- Tests: each type, a missing or non-image file, an oversized image, an animated PNG, a model without image input,
  a resumed session, and the OpenAI-chat and Gemini encodings against recorded request shapes.
- Not verified here: how each provider's current API limits images (count, size), and what Anthropic and OpenAI
  charge per image. Check the providers' documents when writing the design.

## Design (2026-10-28, proposed; nothing built)

The touch points, read from the code: `ToolOutput` is `content: String` + `isError` + `backgroundJob`;
`RequestBlock.toolResult(id:content:isError:)` carries a string; four request encoders turn it into wire JSON
(`AnthropicRequestEncoder`, `OpenAIRequestEncoder`, `ResponsesRequestEncoder`, `AgyRequestEncoder+Content`), plus `ApplePrompt`
(on-device: text only); `WirePayload` and `SessionReplay` persist it; `Compaction` and the context estimate read it.

Slices, each shippable and tested alone:

1. **Value type.** `ImagePart { mediaType: String, data: [UInt8] }` in AskAI. `ToolOutput` gains `images: [ImagePart] = []`;
   `RequestBlock.toolResult` gains `images`. The empty default keeps every existing call site and test unchanged.
2. **Sniff, bound and downscale** in a new `ImageReader` in AskTools (ImageIO/CoreGraphics; macOS only, as ask is today): magic
   numbers for PNG, JPEG, GIF and WebP; refuse animated PNG and files above a read cap (say 20 MiB); scale to at most 2000 px on
   the long side and re-encode until under 4.5 MiB (pi's numbers; to be checked against each provider's limits). `read` calls it
   when the bytes are an image, and returns a text line (type, dimensions, size) plus the part.
3. **Encoders**, each against a recorded request shape: Anthropic (image block inside `tool_result`), OpenAI chat (text
   "(see attached image)", then a user message with `image_url` data URLs), Responses, Gemini/Antigravity (inline data in the
   function response; older models a user turn). The on-device model: text only.
4. **Modality field** on the model catalogue (`inputModalities`), with Codex's decoded value, a default of text for the rest and an
   override in config. A model without image input gets "this model does not support image input", not an image.
5. **Persistence**: images stored beside the session file by content hash and referenced from the payload, so a resumed session
   stays small; the context estimate counts a fixed cost per image until measured.
6. **Budget** across a request: keep the newest images up to a cap, replace older ones by a placeholder in steps (cache-friendly).
7. MCP image results use the same part. Terminal display stays out (TerminalKit 0018).

Order: 1, 2 and 3 for Anthropic first (the smallest end to end), then the other encoders.

## Progress (2026-10-28)

- Slices 1-2 and the PDF/video/format extension: done (`df19552`, `8df567d`).
- **Sandbox (owner: "sandbox should always be followed whenever enabled")**: under a restricted policy the kind of a file is read
  through the verified descriptor, and a video, which AVFoundation can only open by path, is copied from the verified descriptor into
  a private 0700 directory and read from the copy, which is removed after. Test: a restricted policy reads an allowed video and
  refuses a protected one, leaving no copy.
- **Slice 3 (encoders), generalised**: one rule before every encoder (`ImagePart.filtering`, called in `AgentLoop.request`): images
  are sent only when the model is known to take them (`acceptsImages == true`); otherwise the result says why they were not sent.
  Anthropic: inside the tool result. OpenAI chat and Responses: the tool result says the image is attached, and one user message
  after the results carries it (`image_url` data URL / `input_image`), one shared writer for both. Agy and Apple stay on the note.
- **Slice 4 (capability)**: `acceptsImages: Bool?` on `CatalogModel`, `ResolvedModel` and `AgentSettings`. Known true for the
  Anthropic and Codex subscriptions; Codex's `input_modalities` and Copilot's `supports.vision` fill it; `providers.json` models take
  `"images": true|false`; anything else is unknown and withholds, as other harnesses assume text only for an unlisted model.
- **Copilot (owner: second most important; diary 07)**: the catalogue's `limits.vision` (count, bytes, media types) is read and
  applied by `read` (`ImageReader.Allowance`) and by `ImagePart.filtering` (unlisted types, a per-request count that drops the oldest
  to half the allowance); `ask models` shows an IMAGES column. Requests match VS Code Copilot Chat 0.44.0: `Copilot-Vision-Request`
  with an image, `X-Interaction-Id` per user turn, `X-Interaction-Type`, `X-Agent-Task-Id`, `X-GitHub-Api-Version: 2025-05-01`,
  `detail: "auto"`, and its follow-up wording. Live: one 64×64 PNG read correctly on the Messages, Responses and chat routes, and a
  3.3 MB PNG was sent as a 1.1 MB JPEG under the 3 MB limit.
- Not verified: the Gemini/Agy shape; the header's necessity, over-limit behaviour and whether the byte limit is raw or base64 on
  Copilot; the other providers' wires live; other harnesses beyond Copilot (opencode, pi and VS Code were read for Copilot only;
  codex and gemini-cli not yet). Still open: Gemini/Agy inline images, persistence by hash, a context cost per image, MCP images,
  native PDF documents, and the cross-harness review.
