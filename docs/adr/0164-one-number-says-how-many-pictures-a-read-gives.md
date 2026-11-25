---
status: accepted
date: 2026-11-17
---

# 0164 — One number says how many pictures a read gives; its media arguments stay beside the path

## Context

`read` takes twelve arguments, and eight of them matter only for a PDF or a video: `pages`, `render`, `at`, `count`, `every`,
`start`, `end`, `max_images`. In the sessions on this machine (4,141 calls of `read`) none of the eight was given once. The
owner (2026-11-17) asked whether they should be grouped, or split out.

What the sessions say about that zero (`Scripts/measure-tool-arguments.py read`, and the extensions of the paths read):

| Read | Calls |
|---|---|
| a `.png` or `.jpg` | 1,264 |
| a `.pdf`, `.mp4`, `.mov` or `.m4v` | 0 |

The arguments were never given because no PDF and no video was ever read here, not because a model read one and did without.
That is no evidence about them, and the research note already says an argument never given here is not one nobody needs.

Reading the eight for overlap instead found one: **`count` and `max_images` were two numbers for how many pictures**, and they
did not agree. `count: 12` with the limit left at 8 gave the first eight of twelve equal parts: frames up to 6.25 s of a 10 s
video and none of its last third, with a line saying four more were over the limit.

## Decision

1. **`count` is no longer told to a model. `max_images` is how many frames a video gives**, spread evenly from `start` to
   `end`: 4 when the call does not say, at most 20. With `at` or `every` it stays the limit on what they ask for.
2. **`count` is still read, as `max_images`**, when a call gives it and not the other. A model that remembers it, or a
   recorded call, gets the frames it asked for rather than four. Convenience is a requirement (AGENTS.md).
3. **The other seven stay, and stay beside `path`.**
   - Not grouped under one object: the bytes are the same or more, and a nested argument is one more place to get a shape
     wrong (ADR-0157 counted those refusals).
   - Not split into a tool of their own: an image is read 1,264 times through `read` by its path alone, so a second tool
     would be chosen by file type before the file is opened, and would cost a name, a description and `path` again.
   - Not removed: `at`, `every`, `start` and `end` are how a model looks at one moment of a recording, and `pages` and
     `render` at one page of a scan. Nothing measured says they are not needed.

## The probes

| Claim | Probe | Verdict |
|---|---|---|
| The two numbers disagreed | `VideoReader.times` for `count: 12` under a limit of 8 | **Holds**: the last frame at 6.25 s of 10 |
| `max_images: 12` gives twelve frames over the whole video, and 99 gives twenty | `MediaReadTests`, a video written by AVFoundation | **Holds**; with the old wiring both fail |
| `count` alone is still honoured, and `max_images` wins beside it | The same | **Holds** |
| With `at`, `max_images` is still the limit | The same: three times asked, two given, one said | **Holds** |
| The tool list shrinks | `Scripts/measure-request-size.py` | **Holds**: `read` 1,872 to 1,821 bytes; the tool list 10,776 to 10,725 |

## Consequences

- A call that gave both, `count: 4, max_images: 8`, to mean "four frames, and no more than eight", now gets eight. No
  recorded call does.
- `read` has eleven arguments where it had twelve. The saving is 51 bytes; the gain is that one number cannot contradict another.
- **Not known: how models use the seven on real PDFs and videos.** No session here holds one. `measure-tool-arguments.py read`
  after a week that includes them is what would say whether `every`, `start` and `end` earn their 293 bytes.
