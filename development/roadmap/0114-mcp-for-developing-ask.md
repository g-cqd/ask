---
status: in-progress
blocked-by: []
date: 2026-10-28
---

# 0114 — A functional, fast MCP client, and MCP servers for developing ask

Owner wish (2026-10-28 20:04), marked increasingly critical: a functional, high-performance MCP implementation. The owner sees roadmap
items being solved with suboptimal APIs, and says MCP servers such as REA's or apple-docs (`g-cqd/apple-docs`) would help a lot.

The client exists (roadmap 0067: stdio and HTTP transports, config, registry, approval). This item is about making it work well in daily use
and about using such servers.

## REA (owner, 2026-10-28)

"REA" is REA, Reverse Engineer Anything (`morluto/rea`, npm `rea-agents`, rea.tools): one MCP server for reverse engineering native
binaries, JavaScript and Electron apps, .NET assemblies and websites, with agent skills and bridges to Hopper, Ghidra or IDA. With
apple-docs, it is the second real server to run ask against.

## Stress test (2026-10-28)

`Benchmarks/Benchmarks/MCPStress` (`cd Benchmarks && swift run -c release MCPStress [scale]`) measures each layer against the floor beneath
it, with every answer checked:

- codec: writing the request and reading the answer's text with AemiJSON, nothing else: the floor of any client;
- loopback: ask's connection with an in-process server (floor: codec plus the server's own cost);
- stdio: ask's transport with fake servers in C, Python, Node and Bun (`Benchmarks/MCPServers`), floor: a bare blocking client of the
  same child;
- HTTP: ask's transport against Node and Bun servers answering JSON or SSE, floor: the same URLSession stack, one parse an answer.

What it found and what changed in `AskMCP`:

- Every reply was parsed twice (the envelope, then the result from a copy of its bytes). The envelope's parsed `result` now goes to the
  caller as it is. 256 KB replies: ×2.2 of the floor before, ×1.37 on loopback and ×0.94 to ×0.97 on stdio after.
- Every request started a timer task. One watchdog a connection now sleeps until the earliest deadline and moves only for an earlier one.
- Messages went through a queue drained by a task. The caller now sends when nothing else is sending; what is queued meanwhile is sent by
  the sender, in order.
- The stdio line splitter scanned byte by byte with bounds checks and copied each chunk twice. It finds newlines with `memchr` in the
  chunk as delivered and copies a line once.
- Loopback, sequential: 9.9 µs a call before, 5.0 µs after (floor 1.2 µs); 64 in flight: 4.6 µs, now 2.9 µs.

Full run after the changes (scale 1: a million calls for each small loopback case):

```
case                                             per call      rate
codec 2 B                                         1.06 µs    946558 calls/s
loopback server alone 2 B                       149.75 ns   6677894 calls/s
loopback 2 B, 1 in flight                         5.02 µs    199189 calls/s   floor    1.21 µs   x4.16
loopback 2 B, 64 in flight                        2.88 µs    347286 calls/s   floor    1.21 µs   x2.39
codec 4096 B                                      1.32 µs    755751 calls/s
loopback server alone 4096 B                    202.31 ns   4943021 calls/s
loopback 4096 B, 1 in flight                      5.42 µs    184537 calls/s   floor    1.53 µs   x3.55
loopback 4096 B, 64 in flight                     3.05 µs    328263 calls/s   floor    1.53 µs   x2.00
codec 262144 B                                   17.09 µs     58523 calls/s
loopback server alone 262144 B                    3.31 µs    302065 calls/s
loopback 262144 B, 1 in flight                   27.70 µs     36095 calls/s   floor   20.40 µs   x1.36
loopback 262144 B, 64 in flight                  13.79 µs     72517 calls/s   floor   20.40 µs   x0.68
stdio C 2 B                                      20.39 µs     49041 calls/s   floor    7.78 µs   x2.62
stdio C 4096 B                                   22.05 µs     45346 calls/s   floor    9.19 µs   x2.40
stdio C 262144 B                                136.70 µs      7315 calls/s   floor  141.95 µs   x0.96
stdio C 2 B, 16 in flight                         4.55 µs    219813 calls/s
stdio Python 2 B                                 26.85 µs     37247 calls/s   floor   12.43 µs   x2.16
stdio Python 4096 B                              29.08 µs     34383 calls/s   floor   15.73 µs   x1.85
stdio Python 262144 B                           287.53 µs      3477 calls/s   floor  295.73 µs   x0.97
stdio Python 2 B, 16 in flight                    5.11 µs    195845 calls/s
stdio Node 2 B                                   25.90 µs     38604 calls/s   floor    9.65 µs   x2.69
stdio Node 4096 B                                28.49 µs     35100 calls/s   floor   12.93 µs   x2.20
stdio Node 262144 B                             188.50 µs      5305 calls/s   floor  199.76 µs   x0.94
stdio Node 2 B, 16 in flight                      5.02 µs    199279 calls/s
stdio Bun 2 B                                    35.59 µs     28097 calls/s   floor   19.11 µs   x1.86
stdio Bun 4096 B                                 36.66 µs     27277 calls/s   floor   23.00 µs   x1.59
stdio Bun 262144 B                              185.57 µs      5388 calls/s   floor  194.33 µs   x0.95
stdio Bun 2 B, 16 in flight                       5.17 µs    193362 calls/s
http Node JSON 2 B                              341.69 µs      2926 calls/s   floor  329.99 µs   x1.04
http Node JSON 4096 B                           339.60 µs      2944 calls/s   floor  324.66 µs   x1.05
http Node SSE 2 B                               321.05 µs      3114 calls/s   floor  328.70 µs   x0.98
http Node SSE 4096 B                            323.38 µs      3092 calls/s   floor  324.05 µs   x1.00
http Bun JSON 2 B                               334.70 µs      2987 calls/s   floor  321.55 µs   x1.04
http Bun JSON 4096 B                            337.53 µs      2962 calls/s   floor  320.08 µs   x1.05
```

What is left, accepted for now: about 4 µs a call on loopback and 15 µs on stdio over the blocking floor. That is the cost of waiting
asynchronously, the caller suspending and three or four hand-offs between threads, which a blocking single-threaded loop does not pay.
Removing the stdio part would mean replacing Subprocess's pipes with a dedicated blocking reader thread. It is microseconds against tool
calls that take milliseconds; recorded so it is a decision, not an oversight. HTTP is at its floor; URLSession is the cost.

New tests: a shorter timeout after a longer one moves the watchdog (it failed, by its time limit, with the move disabled); 200 calls at
once are each sent once and answered.

## Still owed

- Run ask against the apple-docs server from `g-cqd/apple-docs` and record what fails or is slow: connection time, tool listing, call
  latency, large results.
- Budgets for MCP: connection must not delay the first frame (cold start 50 ms); a call's overhead over the server's own time.
- Close the gaps 0067 still lists that daily use hits first (progress in the transcript, resources if apple-docs serves any).
- Decide how the development of ask itself uses these servers, so API choices are checked against current Apple documentation.

## Open questions

- What "REA" refers to: which server, and where it lives.
