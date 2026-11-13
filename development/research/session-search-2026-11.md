# Search over everything a session holds: what to build (t209, t222, note n26)

2026-11-12. The owner (n26, n42): search sessions, threads, tasks and notes, not bound to the model's context; a tool for the model and
a command for the person; fast, on aemi's kernels, possibly a package of its own reusable for a Swift apple-docs; the index built during
compaction, invisibly. Research first; nothing is built.

## What there is to search (measured on this Mac)

| | |
|---|---|
| Sessions | 180 files, 0.30 GB on disk, 112,164 entries |
| Searchable text (typed lines, replies, tool calls and results, compaction summaries) | about 150 MB |
| A full scan of it in Python (JSON parsed line by line) | about 1 s |
| Tasks and notes | the session board's files: small (kilobytes) |

So the whole corpus is small enough to scan: an index is about latency and ranking, not about feasibility. Encrypted sessions (0179)
can only be searched with their key, so an index of them is encrypted too, or they are scanned when opened.

## What aemi already gives

`AemiKernel.ByteSearch` (SIMD substring search), `AemiText` (bounded Levenshtein: plain, banded, early exit; tokenizer windows and
splits), `HashIndex`, `SparseSet`, `ByteBitmap`; AemiJSON for reading entries without decoding whole sessions. Missing: an inverted
index, a ranking function, and anything semantic.

## Ways to search, and what each costs

1. **Scan, no index.** Each query reads the text (from a cache of extracted text, 150 MB) with `ByteSearch`; typos through `AemiText`'s
   bounded distance on candidate words. Estimated tens to a few hundred milliseconds in Swift (not measured); no ranking beyond counts
   and recency. Nothing to keep in sync.
2. **Lexical index (BM25) with trigrams for typos and substrings.** An inverted index of words (BM25 ranking, the standard for lexical
   retrieval) plus a trigram index for partial words and misspellings; about a fifth to the whole of the text's size; queries in
   milliseconds; updated as entries are written and compacted (t222's "during compaction" is the natural batch point: the entries a
   compaction folds away are exactly the ones the model loses, so they are indexed there at the latest).
3. **Semantic.** Embeddings find a passage by meaning ("where did we decide the cache key?"). On device: Apple's `NLEmbedding` sentence
   embeddings or `NLContextualEmbedding` (no network, no cost, quality modest); a provider's embedding API (better, costs, sends the
   text out). Vectors for 150 MB are hundreds of MB at full size, less quantised.
4. **Hybrid**, the common recommendation for long-context retrieval: lexical and semantic results merged by reciprocal rank fusion,
   optionally reranked by a model. Lexical alone finds exact identifiers, paths and error messages, which are most of what a coding
   session is searched for.

## Proposed shape

- **A package of its own on aemi** (the owner's idea): `AemiSearch`, documents of text with fields, an inverted index with BM25, a
  trigram index, filters, and a snapshot format; nothing ask-specific, so a Swift apple-docs can use it.
- **ask's side:** documents are entries (typed line, reply, tool call and result, summary), tasks and notes, with fields: session,
  thread, kind, role, date, tool, path. Indexed as written and at compaction; kept beside the sessions (encrypted with them when they
  are).
- **The model's tool** `search(query, scope?, kind?, since?, limit?)`: ranked snippets with a reference (`session#entry`) it can read in
  full with a second call. **The person's command** `/search QUERY`: the same results in a picker; choosing one opens the session there.

## Decisions for the owner

1. Start with the scan (1) and measure, or go straight to the index (2)?
2. Semantic now (on-device embeddings, or a provider's API), later, or never?
3. `AemiSearch` as a new aemi package, or inside ask first and moved once it settles?
4. Encrypted sessions: an encrypted index beside them, or searched only when unlocked?
