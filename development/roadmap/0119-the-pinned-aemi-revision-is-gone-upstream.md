---
status: done
blocked-by: []
date: 2026-10-28
---

# 0119 — The pinned aemi revision is gone upstream

Found while building the benchmarks (roadmap 0114). ask, TerminalKit and AemiJSON all pin `Aemi-Studio/aemi` at
`785c6b25cb3f4dc16ca2334fd69428fae4ee0b01`. That commit is no longer on GitHub: `git ls-remote` lists `main` at `f6da05c`, and the
pinned commit is not its ancestor, which points to a history rewrite. SwiftPM refused to resolve it for the Benchmarks package
("could not find the commit"); ask still builds here only because the commit is in the local `.build/repositories` cache. The benchmarks
were built by fetching the commit from that cache, locally.

## Done (2026-10-28)

The owner asked for the pin to be moved everywhere. The counterpart of `785c6b2` on aemi's new history is `f6da05c`: same author, date and
message, and its diff from `785c6b2` is only "Created by Guillaume Coquard" becoming "Created by Gigi" in 33 file headers.

Moved, each resolved against GitHub, built, committed signed as Gigi and pushed, in dependency order:

- on aemi only: AemiRegex `fe9b07f`, TerminalKit `cc0c60c`, AemiMarkdown, AemiProtobuf, AemiSwift, AemiUI, AemiUtilities, and Abysm
  (`f180a85`, cloned for this) then AemiSDR, which pins it;
- AemiJSON `5542d37` (aemi and AemiRegex), then analyzerkit `3d1f811` (aemi and AemiJSON);
- the analyzers arcleak, dolly, deadwood, fcheck and modeler (AemiJSON and analyzerkit);
- benchmark packages in AemiMarkdown and TerminalKit; Atelier's AtelierCore, KittyCode and GitDiffViewer, whose TerminalKit pin
  `554a224` was also off main after the rewrite and moved to `cc0c60c` (five additive commits past its counterpart);
- ask: aemi `f6da05c`, TerminalKit `cc0c60c`, AemiJSON `5542d37`, AemiRegex `fe9b07f` (URL now `g-cqd/AemiRegex.git`, as AemiJSON
  names it), and the Benchmarks package. The quality gate passes on the new graph.

Found on the way: AemiUI's and AemiUtilities' local clones held a second, unpushed copy of the same rewritten history (same commits and
trees, different hashes). Their pin commits were replayed on GitHub's history and pushed as fast-forwards; the old local histories are kept
on a `local-before-aemi-repin` branch. A clone made in a temporary directory has no identity or SSH key set, and its first commit came
out with the wrong author and its push was refused for the wrong account; it was redone with the repository settings the other clones use.
The earlier note that ask's AemiRegex, AemiJSON and TerminalKit pins were also gone was wrong (a broken shell loop); they were on main.
