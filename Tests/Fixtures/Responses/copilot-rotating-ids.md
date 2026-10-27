# Rotating-ID Responses recording

Captured on 2026-10-27 from Copilot's `/responses`, model `gpt-6.1-sol`, for the
non-sensitive prompt `Reply only with AUDIT.` (max_output_tokens 32). HTTP 200.

Every indexed event describes output_index 0, but output_item.added, content_part,
each text delta, and output_item.done all carry distinct item IDs. The final item
contains the whole `AUDIT` text again. The old decoder produced three text blocks
(`AUD`, `IT`, `AUDIT`), displayed and persisted as `AUDITAUDIT`.

The fixture preserves event order, identity differences, indexes, text and usage.
Opaque IDs were consistently replaced, event names normalized to `message` (the
decoder dispatches the JSON type), and irrelevant fields were removed. It is NOT a
byte-exact recording. No credentials, headers, safety/account identifiers, encrypted
reasoning, metadata or billing-specific extensions are included.

The capture also contained `copilot_usage` on response.completed. Its unit semantics
were not verified, so no claim about authoritative credits or charges follows from
this identity regression. ResponsesIdentityTests replay fragmented and whole frames;
Scripts/probe-responses-identity.py checks the real CLI and session persistence.
