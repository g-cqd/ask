---
status: not-started
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
