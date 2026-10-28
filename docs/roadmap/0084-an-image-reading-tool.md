---
status: not-started
blocked-by: []
date: 2026-10-28
---

# 0084 — An image reading tool

Owner request, from `ask-wishes.md`, marked a priority: the model can read an image file.

Today `ReadTool` reads text. The model message type has no image part: an MCP image result is replaced by a
line such as "[image image/png, N bytes: ask cannot show it]" (`MCPResultText`), so no image reaches a model.

## Still owed

- Decide the tool shape first: extend `read` so a path with an image type returns an image part, or add an
  `image` tool. Record the choice here.
- An image content part in `AskAI`'s message model, and its encoding for each provider that accepts images
  (Anthropic, OpenAI Responses, Gemini and the others). A provider or model without image input gets a clear
  tool failure, not a silent drop.
- Limits: file types (PNG, JPEG, GIF, WebP), maximum bytes, and downscaling or refusing an oversized image.
  Stay inside the sandbox read rules: the path is checked like any `read`.
- Session persistence: store the image by reference or by size-capped data, so a resumed session and the
  token count stay sensible. Check what an image costs in the context estimate.
- Show the result in the transcript as a one-line block (type, dimensions, size). Drawing the pixels is out of
  scope.
- The MCP image result can then use the same part. Decide that with the tool shape.
- Tests: each type, a missing or non-image file, an oversized file, an unsupported model, a resumed session.
