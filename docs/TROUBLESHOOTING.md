# Troubleshooting & operational notes

Things that have bitten us or other users, with the honest explanation and the fix. Skim the headings.

If something here is wrong or out of date, fix it — this doc is meant to grow as we hit new failure modes.

> For the v0.2 RAG pipeline — profiles, quantization modes, hybrid
> BM25, schema-v2 migration — read
> [`rag-optimization.md`](rag-optimization.md). This doc covers
> operational gotchas; that doc covers tuning.

---

## "Incompatible index schema_version" / "extractor_version mismatch"

The v0.2 server stores a `meta` table in `index.db` and refuses to
start when the recorded `schema_version`, `extractor_version`,
`embed_model`, `embed_dim`, `quantization`, or chunk-size doesn't match
the current code. A v0.1 index trips this on first start.

```bash
# Rebuild with the active profile (chosen at bootstrap time).
scripts/reindex.sh --force

# Or switch profile while rebuilding.
scripts/reindex.sh --profile pi --force
```

The new pipeline finishes in a fraction of v0.1's wall-clock time
on the same hardware, so the forced rebuild is cheaper than it
sounds. See `rag-optimization.md` for what the meta keys mean.

---

## "no sources found for this question" — but the article exists in Kiwix

Kiwix's full-text search finds it (browse to `http://127.0.0.1:8081/search?pattern=…`), but the RAG answer says "no sources found." This is the most common confusion.

**Why it happens.** The RAG service only searches the *vector index*, not the ZIM directly. The indexer caps how many articles per ZIM get embedded (`RAG_MAX_ARTICLES`). If the article wasn't in the random sample, the vector store doesn't know about it — even though Kiwix can serve it. The model is then handed weak/irrelevant retrieved passages and correctly refuses to fabricate (see `scripts/rag/prompt.py`).

**The fix.** Raise the cap and re-run bootstrap:

```bash
./scripts/bootstrap.sh --bundle minimal --max-articles 30000 --yes   # or --full-index
```

The indexer is cap-aware: ZIMs that were capped get re-indexed at the new cap, ZIMs that were already fully covered get skipped. No manual SQL cleanup needed.

**The deeper truth.** "minimal" means small *download*, not small content. WikiMed is 1.4 GB on disk but holds ~100k real articles. iFixit is 3.3 GB and holds ~260k HTML pages. Default platform caps:

| Platform | Default cap | Why |
|---|---|---|
| Pi | 3,000 per ZIM | CPU-bound; full coverage takes days |
| Mac / Linux / WSL | **unlimited** | GPU/Metal makes full coverage feasible |

The previous global default of 5,000 was sampling ~1% of Wikipedia-style ZIMs and silently missing demo-critical articles.

---

## Indexing is slow

Pace tiers, roughly, for `nomic-embed-text`:

| Setup | chunks/sec |
|---|---|
| Pi 5 CPU | 2–8 |
| x86 CPU (Docker on Mac/Windows without GPU passthrough) | 5–15 |
| Apple Silicon, **native** Ollama (Metal) | 50–150 |
| NVIDIA GPU (Linux or WSL2 with passthrough) | 100–300+ |

If you're below the expected range, the most likely cause is Ollama running on CPU when you have an accelerator available. See *macOS: Ollama is slow* and *WSL2: GPU passthrough* below.

---

## macOS: Ollama is slow even though I have Apple Silicon

**Why it happens.** Docker Desktop on macOS runs containers inside a Linux VM (virtiofs/krunkit). The VM cannot see Metal. So any Ollama running *inside Docker* is CPU-only, no matter how good your Apple Silicon chip is.

**The fix.** Install Ollama natively and let bootstrap reuse it:

```bash
brew install ollama
ollama serve &
ollama pull qwen2.5:7b nomic-embed-text
./scripts/bootstrap.sh --bundle minimal --yes
```

Bootstrap detects the host Ollama at `127.0.0.1:11434` and writes `OLLAMA_URL=http://host.docker.internal:11434` into `compose/.env`. Look for this line in the output:

```
Local Ollama detected on port 11434 — using it instead of the Docker service.
```

Real speedup observed: ~10 chunks/sec (Dockerized CPU) → ~50 chunks/sec (native Metal). 5–10× for embeddings.

---

## macOS: Docker Desktop has too little RAM

Docker Desktop's default memory allocation is often 4 or 8 GB. `qwen2.5:7b` alone is ~5 GB when loaded. Add the embedder, the indexer's SQLite writes, and the WebUI, and the OOM-killer reaps Ollama mid-run. You'll see the indexer crash with:

```
Connection refused
```

followed by a flurry of failed embeds.

**The fix.** Docker Desktop → Settings → Resources → Memory. Push to **12–16 GB** if your Mac has it. Also check for unrelated containers eating budget (`docker ps` — other projects' Postgres/Redis/etc.).

---

## WSL2: GPU passthrough or expect CPU-only speeds

Three buckets on Windows:

| Hardware | Result |
|---|---|
| NVIDIA discrete + `nvidia-container-toolkit` in WSL2 | Full GPU acceleration. Fast. |
| Intel iGPU / AMD APU only | CPU only. Slow. |
| AMD discrete | Mostly slow — ROCm under WSL2 is rough. |

Bootstrap auto-detects `nvidia-smi` and surfaces a warning when WSL2 + no NVIDIA. If you can't add a GPU, drop to `--bundle minimal` and accept CPU-speed indexing.

---

## Pi 4 with 4 GB RAM: indexer OOMs

The Pi 4 with 4 GB struggles to run Ollama and the indexer concurrently. Solution: pull the chat model first, then run the indexer after Ollama is idle. Or use `--no-model` to skip the chat model entirely.

See `docs/deployment/pi-text-only.md` for the full Pi recipe.

---

## "could not write vector blob" / sqlite-vec rejected a chunk

```
sqlite3.OperationalError: Internal sqlite-vec error: could not write vector blob
```

**Why it happens.** Ollama occasionally returns a malformed embedding for edge-case input (very short text, garbage HTML, etc.) — NaN, infinity, zero magnitude, or wrong dimensionality. `sqlite-vec` then refuses to write the vector.

**The fix is already in `scripts/rag/indexer.py`.** Each chunk is now validated before insert; bad chunks log a warning and are skipped. The indexer continues. If you see one of these warnings, the affected article just won't be searchable.

---

## "locking protocol" error during indexing

```
sqlite3.OperationalError: locking protocol
```

**Why it happens.** Both the FastAPI server (`scripts/rag/server.py`) and the indexer hold connections to the same `index.db`. With sqlite-vec's `vec0` virtual tables, concurrent writes can trigger `SQLITE_PROTOCOL` even in WAL mode. Got dramatically worse once native Ollama made writes fast.

**The fix is already in `scripts/rag/server.py`.** The server now opens the DB in **read-only URI mode** (`file:…?mode=ro`) with a 30-second `busy_timeout`. The server can't acquire any write lock, so it can't contend with the indexer.

**If you're still hitting this**, rebuild the rag image — bootstrap now does this automatically on every run, but if you bypassed bootstrap:

```bash
docker compose -f compose/docker-compose.yml build rag
docker compose -f compose/docker-compose.yml up -d rag
```

---

## Indexer crashed mid-run and chunks accumulate as duplicates on re-run

**Why it happens.** The indexer only writes the "this ZIM is done" marker in `indexed_zims` after the article loop completes. If the process dies mid-loop (OOM, container restart, Ctrl-C), no marker is written. Without `--force`, the next run *appended* chunks to the existing partial state.

**The fix is now in the cap-aware resume logic** (scripts/rag/indexer.py): a ZIM with no completion marker is dropped before re-indexing, even without `--force`. Bootstrap is now safe to re-run after any interruption.

---

## SHA-256 verification fails on bundle download

The downloaded ZIM's hash doesn't match the manifest's. Two common causes:

1. **Kiwix rebuilt the ZIM** after the manifest was written. Pull the live hash from `<url>.sha256` and update `bundles/<bundle>/manifest.json`.
2. **The manifest's `sha256` field is empty** (e.g. several entries in `comprehensive` were originally blank). Same fix.

`fetch-bundle.sh` will not silently accept a mismatch — per `CLAUDE.md` checksum policy. If you're seeing this, fix the manifest, don't bypass the check.

---

## Re-running bootstrap to expand coverage

Yes, this just works now. The indexer compares each ZIM's previously-recorded article count against the new effective cap; if the cap was raised (or set to `--full-index`), the previously-capped ZIMs get dropped and re-indexed. Fully-covered ZIMs are skipped.

```bash
# First run: get a fast partial index
./scripts/bootstrap.sh --bundle minimal --max-articles 10000 --yes

# Later: bump coverage
./scripts/bootstrap.sh --bundle minimal --max-articles 50000 --yes

# Eventually: full coverage
./scripts/bootstrap.sh --bundle minimal --full-index --yes
```

Each invocation re-uses whatever's already in `index.db`; iFixit doesn't get re-indexed if its prior coverage was already at the new cap.

---

## "Can I pick any bundle with any model?"

Yes. `--bundle` and `--model` are independent flags. The manifest's `model:` field is a *suggestion* for that bundle's typical hardware, not a constraint. Concrete recipes:

```bash
# Pi 5 with a 1 TB external SSD + full Wikipedia + tiny model + chat
./scripts/bootstrap.sh --pi --bundle comprehensive --model qwen2.5:1.5b

# Same, but no chat model at all — pure search-only
./scripts/bootstrap.sh --pi --bundle comprehensive --no-model

# Mac with native Ollama, balanced bundle, default 7B model
./scripts/bootstrap.sh --bundle balanced --yes
```

In search-only mode the landing page auto-hides the "Ask AI" UI (it reads `/status` and reacts to `search_only: true`).

---

## Demo question doesn't land

The query is real but RAG returns "no sources found." Two possibilities:

1. **The topic isn't in your bundle.** WikiMed is medical-focused — "what is photosynthesis?" only lands if WikiMed happens to have the article and it's in the indexed sample. iFixit can't answer biology questions. Pick demo questions that match your installed ZIMs.
2. **The article exists but isn't indexed.** See the cap section above. Solution: raise `--max-articles` and re-run bootstrap.

A useful sanity check before any demo:

```bash
docker compose exec rag python3 -c "
import sqlite3
db = sqlite3.connect('file:/index/index.db?mode=ro', uri=True)
for r in db.execute(\"SELECT zim_name, COUNT(*) FROM chunks WHERE text LIKE '%<your-keyword>%' GROUP BY zim_name\"):
    print(r)
"
```

Zero rows → your demo question won't work. Pick a different question, or re-index with higher coverage.

---

## Where to watch what's happening

- **Indexer progress (live)**: `docker compose -f compose/docker-compose.yml logs -f rag`
- **Per-ZIM chunk counts**: bootstrap's final summary prints them automatically. Or:
  ```bash
  docker compose exec rag python3 -c "
  import sqlite3
  db = sqlite3.connect('file:/index/index.db?mode=ro', uri=True)
  for r in db.execute('SELECT zim_name, COUNT(*) FROM chunks GROUP BY zim_name'):
      print(r)
  "
  ```
- **What the host Ollama is doing** (if running native): `ollama ps`
- **Resource pressure**: `docker stats`

---

## Pace sanity check on Mac / Apple Silicon

If you're on Apple Silicon and indexing is < 30 chunks/sec, **you're probably still on Dockerized Ollama.** Verify:

```bash
grep OLLAMA_URL compose/.env
```

You want `OLLAMA_URL=http://host.docker.internal:11434`. If it says `http://ollama:11434`, the rag container is using the Docker Ollama container (CPU-only). Start `ollama serve` on the host and re-run bootstrap.

---

## "no sources found" on Wikipedia-style topics despite a successful WikiMed index

Symptom: `/status` shows WikiMed indexed at thousands of articles, the chunk count looks healthy, but every Wikipedia-style question returns "no sources found for this question." Kiwix full-text search finds the article fine.

**Likely cause: MediaWiki HTML extraction is returning empty text.** Sanity check:

```bash
docker compose exec rag python3 -c "
import sqlite3
db = sqlite3.connect('file:/index/index.db?mode=ro', uri=True)
for r in db.execute(\"SELECT zim_name, AVG(length(text)) FROM chunks GROUP BY zim_name\"):
    print(r)
"
```

If WikiMed's avg chunk length is < 100 chars, you're hitting an extraction bug — chunks are just title fragments, not article bodies. The shipped `_html_to_text` in `scripts/rag/indexer.py` uses an anchored per-class matcher to avoid this; older versions (or local edits) using `class_=re.compile(...)` against the joined class string will silently strip Wikipedia bodies because Vector-skin classes like `vector-toc-not-available` contain the substring `toc` from the strip-list.

**Fix.** Rebuild the rag image to pick up the latest extractor, drop the broken WikiMed state, re-index. See *Re-running bootstrap to expand coverage* below for the safe drop+re-index pattern.

---

## Cap-aware logic re-indexes a ZIM I already fully covered

Symptom: you ran `--full-index` (unlimited) on a ZIM and it finished. You re-run bootstrap and it wants to drop+re-index that ZIM again.

**Why it happens.** The cap-aware logic at `scripts/rag/indexer.py` compares the recorded `article_count` to `archive.all_entry_count`. But `all_entry_count` includes *redirects and images* (often ~80% of the archive), not just real HTML articles. WikiMed has 463k total entries but only ~102k actual articles — so a 100% real-article-coverage run records `article_count=80231` which the comparison reads as "only 17% covered."

**Workaround: pin the ZIM as fully covered.** Set `article_count` to a value larger than `all_entry_count`:

```bash
docker compose -f compose/docker-compose.yml exec rag python3 -c "import sqlite3; db=sqlite3.connect('/index/index.db'); db.execute(\"UPDATE indexed_zims SET article_count=999999 WHERE zim_name='wikipedia_en_medicine_maxi_2026-04'\"); db.commit(); print('pinned')"
```

Adjust `zim_name` for your ZIM. After pinning, cap-aware sees `prev_was_capped = 999999 < 463451 = False` and skips re-indexing.

**Proper v0.2 fix** would teach the indexer to track *HTML-article count* (filtered) rather than `all_entry_count` when judging "fully covered." For v0.1 the pin trick is the workaround.

---

## Server and indexer can't be running concurrently (sqlite-vec locking)

Symptom: indexer was happily running, then crashed with:

```
sqlite3.OperationalError: locking protocol
```

at `conn.commit()`.

**Root cause.** `scripts/rag/server.py` opens the index in read-only URI mode with `busy_timeout` — sufficient for normal SQLite locking, but **sqlite-vec's `vec0` virtual tables maintain internal page state across connections that still contends** during writes. The read-only flag isn't enough on its own. Got dramatically worse once native Ollama made the indexer fast enough to commit frequently.

**The canonical workaround** (used throughout this project's history):

```bash
# 1. Stop the FastAPI server — releases its connection entirely
docker compose -f compose/docker-compose.yml stop rag

# 2. Run the indexer in a one-off container with no competing connection
docker compose -f compose/docker-compose.yml run --rm rag \
    python indexer.py --zim-dir /data --index-dir /index \
                       --ollama-url http://host.docker.internal:11434

# 3. After indexing finishes, bring rag back
docker compose -f compose/docker-compose.yml start rag
```

This is reliable even on long overnight runs. `docker compose exec rag python indexer.py` (which bootstrap uses internally) **will still hit the locking issue** for big runs — use this dance for anything beyond a quick test.

A proper v0.2 fix would change `server.py` to open ephemeral per-query connections rather than holding a long-lived one. Trades ~10 ms per query for true zero-contention.

---

## "Why is `index.db` bigger than my ZIM files?"

This is normal and expected for text-heavy archives. Observed ratios:

| Archive | ZIM (compressed) | Index after full coverage | Ratio |
|---|---|---|---|
| WikiMed | 1.4 GB | ~3 GB | **~2.1× ZIM** |
| iFixit (image-heavy) | 3.3 GB | ~1–2 GB | ~0.4–0.6× ZIM |
| Wikipedia full + images (projected) | 115 GB | ~50–80 GB | ~0.5× ZIM |
| Comprehensive bundle (projected) | 411 GB | ~200–300 GB | ~0.5–0.7× ZIM |

**Why.** ZIMs store article content compressed and de-duplicated. The vector index stores, per chunk:

- A 768-dim `float32` embedding = exactly **3 KB**, fixed, regardless of source size
- The chunk text (~800 chars) — **uncompressed**
- A 100-char overlap with the next chunk — duplication

So a 1 GB body of compressed Wikipedia prose blows up into many ~4 KB chunks. Text-heavy archives (WikiMed, Stack Overflow, books) have higher ratios than image-heavy ones (iFixit, where most ZIM bytes are images the indexer ignores).

**You probably don't need to do anything.** Just plan disk accordingly: budget at least **2× the ZIM size** when you size your storage for a text-heavy bundle.

**Future v0.2+ mitigations** under consideration:

- Smaller-dimension embedding models (`all-MiniLM-L6-v2` = 384-dim, halves the vector size).
- Quantised vectors via `sqlite-vec` (`float16` halves storage, `int8` quarters it, with small recall loss).
- `zstd` compression on chunk text before insert.
- Storing only an offset into the ZIM rather than the chunk text itself, re-extracting at query time.

Tracked in `docs/ARCHITECTURE.md` under *Decisions to revisit in v0.2+*.

---

## Auto-shutdown after long unattended indexing

For overnight or multi-day runs where you want the Mac to power off when the indexer finishes:

```bash
# Schedule a hard shutdown 16 hours from now (adjust to your expected ETA + buffer)
sudo pmset schedule shutdown "$(date -v +16H '+%m/%d/%y %H:%M:%S')"

# Run the indexer with caffeinate to prevent sleep during work
caffeinate -di docker compose -f compose/docker-compose.yml run --rm rag \
    python indexer.py --zim-dir /data --index-dir /index \
                       --ollama-url http://host.docker.internal:11434 \
                       --max-articles 0
```

When the indexer exits, `caffeinate` exits, the Mac can sleep. At the scheduled time `pmset` wakes if needed and shuts down. Survives lid-close and sleep.

**Always remember to cancel** if you change your mind or run finishes before you walk away from the keyboard:

```bash
sudo pmset schedule cancelAll
pmset -g sched   # verify nothing is scheduled
```

---

## Bootstrap doesn't pick up my source edits

**Used to be:** `docker compose up` reuses any locally-tagged `allarkive-rag:0.1.0` image, even after you edited `scripts/rag/*.py`. Footgun.

**Now:** bootstrap runs `docker compose build rag` on every invocation before `up`. Cached layers make this near-instant (~5s) when nothing changed. So `./scripts/bootstrap.sh --yes` is now sufficient to ship a code change.

If you're bypassing bootstrap entirely, remember to `docker compose build rag` yourself first.
