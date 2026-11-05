---
status: in-progress
blocked-by: ["0199", "0200"]
date: 2026-11-04
---

# 0201 — A Quick Look extension for Markdown and Mermaid, built with Xcode 27 and deployed from macOS 26

Press space on a `.md` or `.mmd` file in Finder and read it, set in the system font, with diagrams drawn natively. Lives in `AemiMarkdown/Apps/MarkdownLook` (the owner, 2026-11-04); identifiers: app `studio.aemi.MarkdownLook`, extensions `studio.aemi.MarkdownLook.Preview` and `studio.aemi.MarkdownLook.Thumbnail`, exported Mermaid type `studio.aemi.mermaid`. The system previews Markdown as plain text today, and the only Markdown extension installed on the development machine is Obsidian's
(diary 2026-11-04-01, claim 7). Design: `development/research/mermaid-markdown-quicklook-2026-11.md`, section 8.

## What the platform is (probed on macOS 27.0.1, Xcode 27.2, SDK 27.2; the floor is macOS 26, the owner's decision of 2026-11-04)

One extension point, `com.apple.quicklook.preview`; view-based (`QLPreviewingController`) or data-based (`QLPreviewProvider` and `QLPreviewReply`); thumbnails are a separate extension (`QLThumbnailProvider`). The API has not changed since macOS 12.
`.md` and `.markdown` are `net.daringfireball.markdown`; `public.markdown` is declared; `.mmd` and `.mermaid` are unclaimed.

## Phase 0: skeletons and the unknowns

Build both a view-based and a data-based skeleton (the data-based one drawn as a vector, `isBitmap: false` or a `PDFDocument`; a bitmap context is never used for a preview) and measure, release, median and spread over repeated runs through a script (`qlmanage -p` and `-t`, `pluginkit`, signposts around request, handler and first draw): request to first pixel and resident memory for a typical README and a 1 MB changelog.
Also answer, by running them: the memory and time limits of an extension process; whether a sandboxed extension can read images beside the previewed file; whether the user must switch the extension on by hand on macOS 27; **the extension is tested on the current machine (macOS 27.0.1), the owner's decision of 2026-11-04; the 26 floor is a deployment target the compiler checks for API availability, and whether it runs on 26 is unverified and stated as such in the app's README; whether `preparePreviewOfFile` can be written as an `async` method; what importing the unclaimed Markdown extensions does to other apps. Record in the diary; choose in an ADR.

## What is built

- XcodeGen (`project.yml`, deployment target macOS 26.0, built with Xcode 27.2, `projectFormat: xcode16_3`, strict concurrency, `ExistentialAny` and warnings as errors as build settings, as MacFS), thin targets over `MarkdownLookKit` (0199): the container app (reading settings, how to enable the extension), the preview extension, the thumbnail extension (the first screenful drawn with the vector backend into the thumbnail's own context; a thumbnail is an image by contract, the one raster here).
- The preview extension, view-based unless phase 0 says otherwise, on the host 0199 chose (not assumed to be TextKit 2: that host showed a 30 to 40 ms tail on large documents, diary claim 11, and a preview is mostly small ones): reads the file with a stated cap and a visible "truncated" line, parses, lays out the first screen, calls the handler, lays out the rest lazily; diagrams show source and are replaced when laid out in the background; light and dark switch without a new layout; live reflow on resize.
- Supported types `net.daringfireball.markdown` and `public.markdown`, plus an exported type for `.mmd` and `.mermaid` conforming to `public.plain-text`.
- Sandboxed, hardened runtime, **no network, no JIT, no web view, no JavaScript**; remote images are shown as their alt text; links open only by user action under ADR-0129's scheme rules.

## Red first

Logic is tested in `MarkdownLookKit` (attributed-string and scene goldens, allocation ceilings, the typography properties). A probe script fails when the extension is not registered, when the first pixel exceeds the phase 0 budget, or when a hostile Markdown file (the corpus of 0196, deeply nested lists and quotes, a 50 MB file) is not shown within the bound.

## Done when

Space on a Markdown file and on a Mermaid file in Finder shows the document and its diagrams within the budget phase 0 set, in light and dark, for the corpus; thumbnails show the first screen; the numbers are in the diary and the decisions in ADRs.

## Performance and resources, by measurement (research note, section 13)

The extension is a process the system starts for a keypress, so cold start and resident memory are its budgets, set by phase 0: link only what is used (a probe of an AppKit-only view against hosting SwiftUI, by launch time and memory), a startup order file as ask has for its own launch, no Foundation or framework work before the handler is called, fonts and themes resolved lazily,
the file mapped and not copied, layout of the first screen only and the rest after the handler, release of caches when the preview goes away, profile-guided and link-time optimization in this build only (Xcode build settings) if a probe shows the gain. Each kept or reverted by its numbers.

## Not in scope

Distribution (notarised build, a Homebrew cask) until the owner decides it; math typesetting; editing; the iOS Quick Look extension (the kit is written so it could follow).

## Progress (2026-11-05)

The app and both extensions build and run (XcodeGen project, ad-hoc signed): the preview answers with the HTML page and was seen in Quick Look on this machine (macOS 27.0.1); the thumbnail extension is used for Mermaid files and pie charts, but the system's own thumbnail wins for `.md` here. Settings are read from a shared preferences domain through a read-only sandbox exception. Not done: the macOS 26 runtime, cold-start and resident-memory budgets, signing and notarisation (the owner's decision), the host probe.
