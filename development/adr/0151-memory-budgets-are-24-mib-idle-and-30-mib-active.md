---
status: accepted
date: 2026-11-14
---

# 0151 — The memory budgets are 24 MiB idle and 30 MiB active

## Context

ADR-0122's amendment set idle memory at 15 MiB and active at 20 (25 since roadmap 0088), as resident size on a loaded machine.
Both had been over since the Apple on-device model and the PDF, video and pasteboard code arrived: 22.4 MiB idle and 27.7 active
(`Scripts/measure-budgets.py`, 2026-11-14, in this repository). Roadmap 0232 asked where it goes:

- 5.9 MiB of the idle figure was the network stack, loaded at launch by a read of GitHub. ADR-0152 moves that read out.
- About 3 MiB is what the dynamic linker makes resident for four frameworks before any call into them: AppKit, PDFKit and
  AVFoundation (0.9 MB together), FoundationModels (2.6 MB). A program that links Foundation alone and sleeps is 5.66 MB; with
  the four it is 8.78 MB.
- ask's own heap is 0.75 MB live; what it dirties in all (its physical footprint) is 5.6 to 6.4 MB.

Under 15 MiB would need those frameworks loaded on first use: the Objective-C runtime after `dlopen` for three, a helper process
or a late-loaded library for the model. The owner was asked (2026-11-14) and chose to change the budget, keeping the metric.

## Decision

`Budget.idleMemoryMebibytes` is 24 and `Budget.activeMemoryMebibytes` is 30: resident size, measured as before (ADR-0122, on a
loaded machine, by `Scripts/measure-budgets.py`). This replaces the memory numbers of ADR-0122's amendment; its cold-start,
input and action numbers and its rule that checks run under load stand.

## Consequences

- With ADR-0152 the measured idle is 17.2 MiB and active 27.6: the idle ceiling has 6.8 MiB of room, more than the network stack
  costs. So the ceiling alone would not catch a change that loads it at idle again; the before-and-after numbers a change that
  adds memory owes (ADR-0038) still would, and the diary records the count of mapped images to compare (660 without, 668 with).
- Resident size counts shared system pages ask did not choose. It stays the metric because it is the one a person sees in
  Activity Monitor's "Real Memory" and the one every earlier number here is in.
- Linking a framework is now a known cost: a new one is measured the way these were before it is linked.

## Probes

Diary 2026-11-14-04 (the linking costs, the heap, the threads) and 2026-11-14-05 (the gate's numbers before and after).
