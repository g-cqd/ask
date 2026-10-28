---
status: accepted
date: 2026-10-28
---

# 0121 — Port readiness looks at this machine only

## Context

The bash and job tools take `wait_for_port`: the call returns once something accepts connections on a port, for the
case of a server started in the background. The review of 2026-10-28 (roadmap 0079) noted that the tool is allowed
whenever the network setting is not `none`, and asked which hosts it may touch before a domain-limited network policy
(roadmap 0021) exists.

## Decision

1. `wait_for_port` connects to `127.0.0.1` and `::1` only (`PortWait.accepts`). It takes no host argument and never will:
   a readiness probe of another machine is a network request, and belongs under the network policy of roadmap 0021.
2. It is refused when the network setting is `none`, as today. That is stricter than needed for loopback; it is kept so
   that "no network" means no socket at all from the tools.
3. When a host argument is wanted, it is added only together with the domain policy, and goes through the same check
   as every other outbound connection.

## Consequences

A model cannot use readiness to scan a network, or to learn which ports another host has open. A test pins the loopback
address in `PortWait`; changing it fails the gate and needs a new decision.
