# RAG optimization — profiles, quantization, hybrid, custom bundles

The v0.2 RAG pipeline introduces five interlocking knobs that determine how
long indexing takes, how much disk the index occupies, and how good retrieval
quality is. Most users should pick a **profile** and stop there. This page
documents the dials underneath in case you want to tune.

> The v0.1 pipeline indexed each chunk via a serial HTTP round-trip to
> Ollama, stored the full chunk text plus a 768-dim `float32` vector for
> every chunk, and dense-indexed every ZIM. On a Pi with the
> `comprehensive` bundle that was effectively "leave it running for a
> week and hope." v0.2 is the rewrite that makes a Pi viable.

---

## TL;DR

| If you have… | Use profile | Expect |
|---|---|---|
| A workstation, no disk worries | `workstation` | Largest index, best retrieval, fastest indexing on GPU |
| A laptop (default) | `laptop` | 4× smaller index than v0.1, dense everywhere, batched embeddings |
| A Raspberry Pi 4/5 on USB SSD | `pi` | Index roughly 10–20% of ZIM size, BM25 fallback for ZIMs ≥ 4 GB |

```bash
# At install time
./scripts/bootstrap.sh --profile pi

# After install
./scripts/reindex.sh --profile pi --force
```

The profile is saved to `compose/.env` as `RAG_PROFILE` and reused on every
run of `indexer.py`.

---

## Profile presets

Defined in [`scripts/rag/profiles.py`](../scripts/rag/profiles.py).

| Knob | `pi` | `laptop` | `workstation` |
|---|---|---|---|
| `chunk_size` (chars) | 2000 | 2000 | 1500 |
| `chunk_overlap` | 200 | 200 | 200 |
| `quantization` | `int8` | `int8` | `float32` |
| `hybrid` (BM25 for big ZIMs) | **on** | off | off |
| `hybrid_threshold_gb` | 4.0 | — | — |
| `batch_size` (chunks per `/api/embed`) | 16 | 64 | 128 |
| `embed_model` (recommended) | `nomic-embed-text` | `nomic-embed-text` | `nomic-embed-text` |

Any field can be overridden by the matching `RAG_*` env var or `indexer.py`
CLI flag. The override order is **CLI flag → env var → profile preset →
fallback**.

### Why these defaults

- **Chunk size** is bigger than v0.1's 800 because long-form articles
  retrieve better with longer context and because larger chunks mean
  fewer rows + fewer embed round-trips. 2000 chars fits comfortably in
  every supported embedding model's input window.
- **`int8` quantization** is the new default everywhere except
  `workstation`. With unit-normalised cosine embeddings, the recall hit
  vs `float32` is under one MTEB point on common models — measurable in
  benchmarks, not in practice.
- **Hybrid mode on the Pi** is what makes the `comprehensive` bundle
  realistic. The 115 GB Wikipedia with images and 75 GB Stack Overflow
  ZIM dwarf everything else; dense-indexing them on a Pi was the only
  reason "weeks" was a real number. Skipping dense for those and
  querying their built-in Xapian index instead trades a small
  retrieval-quality hit for a multi-day indexing saving. Smaller ZIMs
  (WikiMed, iFixit, the SE family) still get full dense coverage.
- **Batch size** is the chunks-per-`/api/embed` request size. On CPU,
  16–64 is the sweet spot; larger batches don't help and start
  competing with the page cache. On a GPU laptop, 128+ saturates the
  inference engine.

---

## Schema v2 in one paragraph

The index DB (`/index/index.db`) is SQLite plus the
[`sqlite-vec`](https://github.com/asg017/sqlite-vec) virtual-table
extension. Each indexed chunk is **one** row in `chunks` with the columns
`(zim_name, article_path, chunk_idx, title, char_offset, char_len)` and
**one** matching row in the `chunk_embeddings` virtual table holding the
vector. The chunk text is **not** stored — at query time the RAG server
reads the article from the ZIM and slices `[char_offset:char_offset+char_len]`
using the same `textproc.html_to_text` extractor the indexer used. The
extractor is versioned in `meta.extractor_version`; the server refuses to
start if it has drifted from the version recorded at index time. The full
meta keys:

```
schema_version    = 2
extractor_version = 2
embed_model       = nomic-embed-text
embed_dim         = 768
quantization      = int8|float32
chunk_size        = 2000
chunk_overlap     = 200
```

Mismatch on any of these is fatal at startup. `scripts/reindex.sh --force`
is the one-step fix.

---

## Storage savings vs v0.1

Per-chunk index overhead, approximate, on a 2000-char chunk:

| Pipeline | Vector | Text | Row overhead | Per chunk | vs ZIM (rough) |
|---|---|---|---|---|---|
| v0.1 (`float32`, full text, 800 chars) | 3,072 B | ~800 B | ~150 B | **~4 KB** | ≈ ZIM size |
| v0.2 `laptop` (`int8`, offset-only, 2000 chars) | 768 B | 0 | ~150 B | **~920 B** | ~25% of ZIM |
| v0.2 `pi` (`int8`, offset-only, 2000 chars, hybrid for big ZIMs) | 768 B | 0 | ~150 B | **~920 B** *for small ZIMs only* | ~10–15% of ZIM |

The Pi number is dramatic because the big ZIMs contribute 0 bytes of
vector storage in hybrid mode — their BM25 index is already inside the
ZIM (Kiwix ships a Xapian index in every published ZIM).

---

## Hybrid retrieval semantics

When `RAG_HYBRID=1` (or the `pi` profile), the indexer:

1. Walks each ZIM file. If the file size is at or above
   `RAG_HYBRID_THRESHOLD_GB`, it writes a row to `indexed_zims` with
   `mode='bm25'` and **no** chunk rows.
2. Otherwise it indexes the ZIM densely as usual.

At query time, the server:

1. Embeds the query, packs it for the active quantization mode, and runs
   the standard sqlite-vec KNN over `chunk_embeddings` to get up to
   `RAG_TOP_K` dense hits.
2. For each `bm25` ZIM, runs `libzim.search.Searcher` with the raw query
   text and pulls up to `RAG_BM25_K` results.
3. Merges both rankings via reciprocal rank fusion
   (`score = Σ 1/(k + rank)`) and keeps the top `RAG_TOP_K` unique
   `(zim_name, article_path)` keys.
4. For each surviving passage, reads the article from the ZIM and
   returns either the offset-slice (dense hit) or the first 2000 chars
   (BM25 hit) as the citation context.

The two retrievers see different signals — semantic similarity vs.
keyword overlap — and RRF biases toward results that score in both,
which empirically reduces "no sources found" misses on the Pi profile.
The trade-off is that BM25 hits don't pinpoint *where* in the article
the match was; the server defaults to the article head and lets the LLM
extract what it needs. If you want exact passage targeting, run the
`laptop` profile (full dense).

---

## Custom bundles

The named bundles (`minimal`, `balanced`, `comprehensive`) ship with vetted
manifests. The new `custom` bundle is for anything else.

```bash
# Add by Kiwix library handle (resolved against download.kiwix.org)
scripts/fetch-bundle.sh custom --add wikipedia_en_simple_all_maxi_2026-03

# Add by full URL (no resolution; used as-is)
scripts/fetch-bundle.sh custom --add https://download.kiwix.org/zim/other/foo.zim

# Combined: add several at once
scripts/fetch-bundle.sh custom \
    --add wiktionary_en_all_maxi_2026-01 \
    --add ifixit_en_all_2025-12 \
    --add https://example.com/my-zim.zim
```

What happens:

1. `scripts/build-custom-manifest.py` is called with the `--add` specs.
   Each spec is either a full URL (kept verbatim) or a Kiwix handle
   resolved through the project-prefix → category map (Wikipedia →
   `/zim/wikipedia/`, Stack Exchange family → `/zim/stack_exchange/`,
   iFixit → `/zim/ifixit/`, etc.). Sizes are populated from HEAD
   requests.
2. The resulting `bundles/custom/manifest.json` is written (or appended
   to, if it already exists). This file is **gitignored** — it is
   per-user state, not project state.
3. The normal fetch-bundle download + SHA-256 verify path runs against
   the new manifest.

You can also chain through `bootstrap.sh`:

```bash
scripts/bootstrap.sh --bundle custom \
    --add wiktionary_en_all_maxi_2026-01 \
    --add https://example.com/my-zim.zim
```

### What `--add` does not do

- **It does not check licenses.** `bundles/custom/LICENSE.md` is a
  template; you own the license-tracking burden for self-supplied
  archives. See `THREAT_MODEL.md` on poisoned-content risk.
- **It does not resolve every handle.** Project families that aren't in
  the prefix table will be rejected with an error pointing you at
  [library.kiwix.org](https://library.kiwix.org/) to find the full URL.
  Adding a new mapping is one line in
  [`scripts/build-custom-manifest.py`](../scripts/build-custom-manifest.py).
- **It does not pin SHA-256s.** The manifest is seeded with an empty
  `sha256` field; `fetch-bundle.sh` falls through to the Kiwix-side
  `.sha256` URL for verification. If you intend to redistribute your
  custom bundle, pin the hash after the first download.

---

## Migrating from v0.1

If you ran `bootstrap.sh` before this commit, the old `index.db` is
incompatible. The server refuses to start with:

```
RuntimeError: Incompatible index schema_version='None'; this server
expects schema_version=2. Run: scripts/reindex.sh --force
```

Two ways out:

```bash
# Wipe and rebuild with the active profile.
scripts/reindex.sh --force

# Or, if you want a specific profile:
scripts/reindex.sh --profile pi --force
```

The new pipeline finishes in a fraction of the v0.1 wall-clock time on
the same hardware, so the migration is cheaper than it sounds.

---

## Tuning knobs (env vars)

All optional — leave unset to use the profile preset. Documented in
[`compose/.env.example`](../compose/.env.example).

| Env var | Type | Effect |
|---|---|---|
| `RAG_PROFILE` | enum | `pi` \| `laptop` \| `workstation` |
| `RAG_QUANTIZATION` | enum | `int8` \| `float32` |
| `RAG_CHUNK_SIZE` | int | characters per chunk |
| `RAG_CHUNK_OVERLAP` | int | overlap between adjacent chunks |
| `RAG_BATCH_SIZE` | int | chunks per `/api/embed` request |
| `RAG_HYBRID` | bool | enable BM25 fallback for big ZIMs |
| `RAG_HYBRID_THRESHOLD_GB` | float | ZIM-size threshold for hybrid mode |
| `RAG_TOP_K` | int | passages returned per query |
| `RAG_BM25_K` | int | BM25 candidates per hybrid ZIM before RRF |
| `RAG_MAX_DISTANCE` | float | L2 cap on unit-normalised vectors |
| `RAG_MAX_ARTICLES` | int | per-ZIM article cap; 0 = unlimited |

---

## Pre-built indexes — feasibility note (not yet shipped)

The v0.2 storage work (offset-only, int8 quantization) is a precondition
for shipping pre-built indexes alongside the ZIM bundles — the index
file would otherwise be larger than the ZIM and a poor Pi user
experience. With the new pipeline a comprehensive index drops to roughly
the size of the smaller ZIMs in the bundle, which is realistic to
distribute.

This is on the `v0.2 Candidates` list in `ROADMAP.md`, not shipped. If
you want it sooner, file an issue.
