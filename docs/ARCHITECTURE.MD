# ARCHITECTURE.md

How AllArkive is structured. Read this before changing any layer.

## Design principles

1. **Three loosely-coupled layers.** The archive can run without the AI. The AI can run without RAG. The glue should never assume the layers are co-located.
2. **No internet at runtime.** Once installed, every layer must function with zero outbound network calls. Updates are explicit and user-initiated.
3. **Default-local.** Every service binds to `127.0.0.1`. Remote access is an opt-in deployment pattern, not a default.
4. **Replaceable parts.** Kiwix, Ollama, Open WebUI are upstream tools. We pin versions, document the integration surface, and avoid deep coupling.
5. **Honest output.** Any model response that surfaces in the UI shows its sources. No source = no answer.

## The three layers

### Layer 1 — Archive (Kiwix + ZIM)

**Purpose**: serve static, offline copies of large knowledge bases.

**Components**:
- `kiwix-serve` — reads ZIM files and exposes an HTTP API + UI.
- ZIM files — Kiwix's packaged format. We don't generate ZIMs; we curate which ones to bundle and document how to add more.

**What we own**:
- The bundle manifests (`bundles/<name>/manifest.json`): list of ZIMs, source URLs, SHA-256 checksums, license metadata.
- The `fetch-bundle.sh` script that downloads and verifies a bundle.
- The `kiwix-serve` config (port binding, library file, CORS).

**What we don't own**:
- ZIM creation. Upstream Kiwix and the OpenZIM project handle that.
- Content correctness inside ZIMs.

**Default port**: `8081` (loopback only).

### Layer 2 — Local AI (Ollama + Open WebUI + RAG)

**Purpose**: answer natural-language questions using the local archive.

**Components**:
- **Ollama** — runs open-weight models (Llama, Mistral, Qwen, etc.) on CPU or GPU.
- **Open WebUI** — chat interface, talks to Ollama over its HTTP API.
- **RAG pipeline** (ours) — sits between the user query and the model:
  1. Query → embedding → vector search over an index built from ZIM content.
  2. Top-k passages retrieved with source URLs.
  3. Passages + query → model with a strict prompt template that requires citations.
  4. Model output post-processed to surface citations as clickable links into Kiwix.

**What we own**:
- The RAG pipeline: indexing, embedding choice, retrieval, prompt template, citation enforcement.
- The default model recommendation (updated as better open-weight models ship).
- The minimum/recommended/ideal hardware specs.

**What we don't own**:
- Ollama internals. Open WebUI internals. Model weights.

**Default ports**:
- Ollama: `11434` (loopback only)
- Open WebUI: `3000` (loopback only)
- RAG service: `8000` (loopback only)

**Honesty**: the model can hallucinate. Every response surfaces sources. UI says "checkable, not infallible" near every chat surface. See `DESIGN.md` for the exact wording.

### Layer 3 — Glue

**Purpose**: turn three loose tools into something one person can install and use.

**Components**:
- `compose/docker-compose.yml` — the one-command install of the full stack.
- `compose/docker-compose.pi.yml` — ARM / low-RAM variant (smaller model, no embedding GPU, text-only bundle).
- `scripts/bootstrap.sh` — first-run setup: pull images, fetch default bundle, index for RAG, start services.
- `scripts/fetch-bundle.sh` — download + checksum-verify a named bundle.
- `landing/` — a static landing page served on `localhost:8080`. Single entry point: search the archive, chat with the AI, see what's installed, see disclaimers.
- `docs/` — install guides, deployment patterns, threat model.

**Where most of the work goes.** The individual upstream tools work. The hard part is making them work together so the user doesn't need to understand each one.

## Data flow (RAG query)

```
User
  │ "How do I bleed a radiator?"
  ▼
Landing page (localhost:8080)
  │
  ▼
Open WebUI (localhost:3000)
  │ POST /api/chat
  ▼
RAG service (localhost:8000)
  │ 1. Embed query
  │ 2. Vector search → top-k passages from ZIM index
  │ 3. Build prompt with passages + citation requirement
  ▼
Ollama (localhost:11434)
  │ Generate response constrained to cite passages
  ▼
RAG service
  │ 4. Validate citations exist in retrieved passages
  │ 5. Rewrite citations as kiwix:// links
  ▼
Open WebUI → user
  Response with [1], [2], [3] linking back to
  http://localhost:8081/viewer#wikipedia/...
```

If retrieval returns nothing relevant, the RAG service returns "no sources found for this question" rather than letting the model freewheel.

## Deployment patterns (v0.1)

We support and document four hardware patterns. Anything else is unsupported in v0.1.

### A — Single laptop (default)
Full stack on one machine. Recommended starting point for most users.
- All three layers in one `docker-compose up`.
- Default bundle = "balanced".
- See `docs/deployment/laptop.md`.

### B — Pi text-only / low-power
A cheaper, slower install. Proves the project runs on small hardware.
- Smaller model (e.g. Qwen 3B or quantised 7B).
- Text-only bundle (no Wikipedia images).
- USB SSD required (SD cards are not acceptable for the archive).
- See `docs/deployment/pi-text-only.md`.

### C — Pi archive-only node
No AI, just the archive. Useful as a read-only library other devices on the LAN can talk to. Also useful for testing the "AI box dies but the archive survives" scenario.
- Just `kiwix-serve` on the Pi with a USB SSD.
- The AI runs on a separate machine and points at this Pi for retrieval.
- See `docs/deployment/pi-archive-only.md`.

### D — Two-machine split
AI on a beefier desktop, archive on the Pi (pattern C). The RAG service points at the Pi for ZIM access.
- Same compose, different env vars (`KIWIX_HOST=pi.local`).
- LAN-only. Still default-local from the AI side.
- See `docs/deployment/split.md`.

## Storage layout (per machine)

```
/var/lib/allarkive/
├── zim/                 # ZIM files (large, slow disk OK)
├── index/               # RAG vector index (smaller, fast disk preferred)
├── models/              # Ollama model store
└── data/                # Open WebUI sqlite + user prefs
```

On Pis, this lives on the USB SSD, mounted at `/mnt/ssd/allarkive`. SD cards are for OS only.

## Network topology

### Default (single laptop)
All services bound to `127.0.0.1`. Browser hits `localhost:8080`. Nothing on the LAN, nothing on the internet.

### LAN access (opt-in)
Bind the landing page to `0.0.0.0`, put it behind a reverse proxy (Caddy or nginx), require auth. Documented in `docs/deployment/lan-access.md`. Not a default.

### Internet access (strongly discouraged for v0.1)
Out of scope. Documented as "here is what would need to be true; we don't recommend it yet."

## Pinning and reproducibility

- **Image tags**: pin every Docker image to a digest (`@sha256:...`), not a tag. Renovate/Dependabot bump them.
- **Models**: pin to a specific Ollama model tag and document the SHA. Don't auto-update on user machines.
- **ZIMs**: every bundle manifest pins the upstream URL and SHA-256.
- **Scripts**: shellcheck-clean, version-pinned tools (`apt install -y kiwix-tools=2.x.y` etc.).

## What's deliberately out of scope for v0.1

See `ROADMAP.md` for full list. Headlines:
- No clustering, no replication.
- No mesh / serverless transport.
- No phone apps.
- No specialised bundles for medical or agricultural use.
- No hardened/airgap-only build target.
- No telemetry. Ever.

## Decisions made in Milestone 4

- **Vector DB**: sqlite-vec. Embedded SQLite extension — no extra service, no daemon, no port.
  Index lives at `$ALLARKIVE_DATA_DIR/index/index.db`.
- **Embedding model**: `nomic-embed-text` via Ollama (768 dimensions). Pulled alongside the
  chat model by `bootstrap.sh`. Runs fully offline once downloaded. **Indexing is the slowest
  part of bootstrap**: every ZIM chunk is embedded through Ollama, which on CPU runs at
  roughly 5–15 chunks/sec. For the balanced bundle this is several hours; the indexer is
  resumable and idempotent, so it's intended to run in the background after bootstrap returns.
  Kiwix browsing works immediately; RAG answers improve as index coverage grows.
- **RAG integration with Open WebUI**: the RAG service exposes an OpenAI-compatible API on
  port 8000. Open WebUI is configured via `OPENAI_API_BASE_URLS` to show `allarkive-rag` as
  a selectable model alongside native Ollama models.
- **Citation format**: `[N]` inline markers in the model response are rewritten by the RAG
  service to Markdown links pointing at `http://127.0.0.1:8081/{zim_name}/{article_path}`.

## Decisions to revisit in v0.2+

These are not commitments, just things we noted while building v0.1:

- Embedding model: `nomic-embed-text` is the v0.1 default; better recall vs. speed tradeoffs
  exist (e.g. `mxbai-embed-large`, `all-minilm`).
- Whether RAG should also surface "related entries you didn't ask about."
- Multi-language retrieval and response.
- Bundle deltas (don't re-download 50 GB to update).