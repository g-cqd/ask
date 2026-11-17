---
status: accepted
amends: ADR-0130
date: 2026-11-17
---

# 0163 — A search adds nothing to the tool list: what it finds is called through `dispatch_call`

## Context

A server with too many tools to list stands behind `search_catalog` and `dispatch_call` (ADR-0100), and a search also
**promoted** its matches: up to eight per server were offered as `mcp__server__tool` from the next request on. So a found tool
could be called two ways. ADR-0130 said one of the two should go, preferred to keep the call and drop the promotion, and left
the choice to a measurement that was owed: what a promotion costs the provider's prompt cache, and which way models call.

The owner (2026-11-17) asked for the tools that overlap to be consolidated, the three MCP tools among them.

## The measurement

`Scripts/measure-cache-after-search.py` reads the sessions on this machine: for each search, what the next request read from
the cache. A cache starts with the tool list, so a search that changes the list should cost the whole conversation.

| The search | What it offered | Cache read by the next request | Model |
|---|---|---|---|
| `capabilities` on `rea` | new tools | 0 of 196,540 tokens | gpt |
| `inspect_web_network_capture` on `rea` | new tools | 0 of 203,133 | gpt |
| the same again | the same tools | 204,032 of 206,354 | gpt |
| `run command shell` on `xcode` | new tools | 0 of 90,729 | claude |
| `directory` on `xcode` | new tools | 0 of 44,361 | gpt |
| `execute shell` on `xcode` | nothing: no match | 232,832 of 238,582 | gpt |
| no words (the names) | nothing | 559,336 of 561,651 | gemini |

Every search that changed the list cost the next request its whole cache, four of four, on both protocols; every search that
did not, kept it, three of three. A request that follows no search misses 1.8% of the time (659 of 35,771).

Which way models call: a promoted tool 5 times, `dispatch_call` 0, with both offered and the search saying the first.

## Decision

1. **Promotion is removed** (ADR-0130's option A). `search_catalog` reads the catalog and changes nothing; the tool list is
   the same after a search as before it. `MCPCatalog.promote` and the `/promoted` group are gone.
2. **`dispatch_call` is the one way to call what a search found.** The search's description says so.
3. **The three tools stay three.** `search_catalog` reads ask's own catalog; `dispatch_call` runs another program's tool,
   outside the sandbox, and is asked about under the name of the tool it calls; `server_resource` reads the resources of any
   server, the ones offered whole included, so it is offered on another condition than the two. ADR-0130's reasons against one
   tool with an action argument (no required fields a provider can check, approval read inside the arguments) are unchanged,
   and merging saves a name and a header.

A full reread of 200,000 tokens is the largest single delay ask can cause itself, and the price of a tool list that moves.

## The probes

| Claim | Probe | Verdict |
|---|---|---|
| A search leaves the tool list as it was | `probe-mcp` B: the tools of the request after the search, against the first | **Holds**; on the binary before (`79bb236d`) it fails, with `mcp__many__t17` offered |
| The same, in process, for no words, one match, eight, none | `MCPExposureTests`, four cases | **Holds** |
| A model calls what it found through `dispatch_call` when that is the one way | The real binary, `claude-haiku-5-5`, the owner's `xcode` server (54 tools): find and call a tool | **Holds**: one search, one `dispatch_call` of the right shape; the request after the search read all 12,672 cached tokens |
| A tool the server withdrew is no longer called | `MCPExposureTests` | **Holds** |

## Consequences

- The arguments of a `dispatch_call` are checked by the server, not by the provider against a schema: the model reads the
  schema in the search's result. ADR-0100 already cuts a long schema there, and says the cut.
- **Not known: whether other models call through `dispatch_call` as readily.** One model, one prompt, is not a rate.
  `Scripts/measure-tool-arguments.py dispatch_call` counts it in later sessions.
- Not built, and the owner's to ask for: letting a call of `mcp__server__tool` that is not offered reach a searched server's
  tool, for a model that guesses the name another harness would use.
