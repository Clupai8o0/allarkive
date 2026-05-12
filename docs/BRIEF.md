# AllArkive — Technical Brief

A self-contained reference for a writer or speaker. Assumes zero prior context. Read top to bottom, then cherry-pick.

---

## 1. The one-line pitch

> A private, offline research assistant that runs on your own hardware, with citations you can check.

A self-hostable knowledge ark: a curated offline library (Wikipedia, repair guides, Stack Exchange, public-domain books) plus a local LLM (Ollama + Open WebUI) plus a retrieval pipeline that answers questions only from the library, with clickable citations back to the source articles.

The framing the maintainers explicitly use is **resilience, privacy, censorship resistance, and educational access** — not prepper bunkers, not "the internet is going to collapse." That distinction matters; it's enforced in the design docs and the public copy.

---

## 2. The people and the moment

- **Built by**: Sam and Sham. Two-person maintainer team. Public copy is always "we" — never single-founder voice.
- **License**: AGPL-3.0 for the glue code (this repo). Copyleft is deliberate — if someone runs a fork as a service, improvements have to flow back. Each bundled archive keeps its own upstream license (Wikipedia CC-BY-SA, iFixit CC-BY-NC-SA, Project Gutenberg public-domain-ish, etc.).
- **Public debut**: BSides Melbourne, **May 16–17, 2026**. Audience is infosec — skeptical, allergic to hype. v0.1 alpha ships alongside that talk.
- **Hosting**: GitHub primary, Codeberg mirror via a GitHub Action. Resilience-by-mirroring is the project's own ethos applied to itself.

---

## 3. The problem space (why this exists)

The brief that the docs make, plainly:

1. **Cloud-tenant fragility.** Most "AI assistants" rent compute, models, and content from third parties. Outage, billing, ToS, or policy change breaks the user.
2. **Censorship.** Wikipedia, Stack Exchange, and similar are blocked in different jurisdictions at different times. Once a ZIM file is on local disk, no operator can quietly remove it.
3. **Surveillance.** Every cloud LLM query is a logged event somewhere. Local inference removes that channel.
4. **Hallucinations presented without evidence.** Even when cloud models are right, the user can't check them. AllArkive forces every answer through a retrieval step against a known corpus and renders the citations inline.

The product is the *boring* version of all of this — not a manifesto, just plumbing that runs on a laptop or a Pi.

---

## 4. Architecture — three loosely-coupled layers

The locked decision: each layer must be replaceable and must work without the others where it makes sense.

```
┌──────────────────────────────────────────────────────────┐
│  Layer 3 — Glue                                           │
│  nginx landing page (port 8080) + scripts + compose       │
│  Single entry point. Proxies /api/rag/* to RAG service.   │
└──────────────────────────────────────────────────────────┘
            │                              │
            ▼                              ▼
┌────────────────────────┐   ┌──────────────────────────────┐
│  Layer 1 — Archive     │   │  Layer 2 — Local AI          │
│  Kiwix-serve (8081)    │   │  Ollama (11434)              │
│  Serves .zim files.    │◀──│  Open WebUI (3000)           │
│  Runs alone if needed. │   │  RAG service (8000)          │
└────────────────────────┘   └──────────────────────────────┘
```

Each service is a pinned container — no `:latest` allowed anywhere in this project.

### 4.1 Pinned versions

| Service | Image | Notes |
|---|---|---|
| Archive | `ghcr.io/kiwix/kiwix-serve:3.8.2` (digest pinned) | Auto-scans `.zim` dir every 30s |
| LLM runtime | `ollama/ollama:0.22.1` (digest pinned) | CPU default; optional `--profile gpu` for CUDA |
| Chat UI | `ghcr.io/open-webui/open-webui:0.9.2` (digest pinned) | Telemetry forced off via three env vars |
| RAG | Locally built `allarkive-rag:0.1.0` | Python 3.11, FastAPI, OpenAI-compatible API |
| Landing/gateway | `nginx:1.27.3-alpine` (digest pinned) | Serves `landing/`, proxies `/api/rag/` |

### 4.2 Default ports — all bind to `127.0.0.1`

`8080` landing • `8081` kiwix • `3000` Open WebUI • `8000` RAG • `11434` Ollama. Remote access is opt-in and documented separately (`docs/deployment/lan-access.md`).

### 4.3 Models (pinned by name+tag in bootstrap)

- **Chat**: `qwen2.5:7b` (default), `qwen2.5:3b` (Pi 8 GB), `qwen2.5:1.5b` (Pi 4 GB)
- **Embedding**: `nomic-embed-text` (768-dim)

### 4.4 Data layout

```
/var/lib/allarkive/        # /mnt/ssd/allarkive on Pi (USB SSD — never SD card)
  ├── zim/      # the archive
  ├── index/    # sqlite-vec vector index
  ├── models/   # Ollama model store
  └── data/     # Open WebUI sqlite + chat history
```

The SD-card-fails-under-random-write rule is a real lesson learned, not a stylistic choice — Pi deployments are required to mount a USB SSD.

---

## 5. The RAG pipeline — the interesting engineering bit

This is the part worth demoing on stage. It's small (a few hundred lines of Python in `scripts/rag/`) and intentionally simple, but every piece is doing real work.

### 5.1 Indexer (`indexer.py`)

1. Opens ZIM files via **libzim** (the official Kiwix Python binding).
2. Strips HTML with BeautifulSoup, leaves plain article text.
3. Chunks at **800 chars, 100-char overlap**.
4. Embeds each chunk with `nomic-embed-text` over Ollama's HTTP API (768-dim float32 vectors, L2-normalized).
5. Stores chunks + embeddings in **sqlite-vec** at `index/index.db`. No separate vector daemon — it's a SQLite extension.
6. Idempotent: skips ZIMs whose mtime hasn't changed; commits every 50 chunks.
7. Per-ZIM caps (`--max-articles`, `--large-max-articles` for huge ZIMs like Gutenberg) keep indexing tractable.

### 5.2 Retrieval server (`server.py`)

- FastAPI, exposes an **OpenAI-compatible `/v1/chat/completions`** endpoint. This is the lever that makes the whole project work — Open WebUI is wired to it via `OPENAI_API_BASE_URLS=http://rag:8000/v1`, so the RAG pipeline appears in the UI as just another "model."
- Flow:
  1. Embed user query with same `nomic-embed-text` model.
  2. KNN search over normalized vectors in sqlite-vec, top-K=5, drop anything beyond `RAG_MAX_DISTANCE` (default 1.0).
  3. **If no passages survive the filter, return a "no sources" message at the API level.** The LLM is never given the chance to answer ungrounded.
  4. Otherwise, build prompt with numbered passages.
- Side endpoints: `/status` returns binding mode, installed archives, model names, index readiness; `/health` for Docker.

### 5.3 Prompt (`prompt.py`)

System prompt enforces two rules:
- Every claim must carry an inline `[N]` marker matching a passage.
- "Do not invent citations. If you cannot support a statement, omit it."

### 5.4 Citation rewriter (`citations.py`)

Post-processes the model's response, turning `[N]` markers into Markdown links that point back to the actual Kiwix article URL: `http://127.0.0.1:8081/{zim_name}/{article_path}`. Click a citation → land on the source article in the archive viewer. The chain — query → vector search → LLM → cited answer → click-through to the original ZIM article — is the whole product.

### 5.5 Why this design is interesting

- **sqlite-vec, not pgvector/Qdrant/Chroma.** No daemon, no schema migration, the index is a single file you can rsync. Trade-off: no clustering, no fancy reranking. Fine for v0.1.
- **OpenAI-compatible shape.** Open WebUI doesn't know AllArkive exists — it just sees a model called `allarkive-rag`. Any future client that speaks OpenAI chat completions is automatically compatible.
- **Refusal is enforced upstream of the model.** This is the architectural answer to "how do you stop the LLM from hallucinating." You don't ask politely in a system prompt and hope; the API itself refuses to call the model when retrieval returns nothing.

---

## 6. Deployment topologies

Four patterns ship in v0.1, all from the same compose files.

| Pattern | Hardware | Compose file | Bundle | Model |
|---|---|---|---|---|
| **A. Single laptop** | One machine | `docker-compose.yml` | balanced | qwen2.5:7b |
| **B. Pi text-only (full stack)** | Pi 4 4–8 GB + USB SSD | `docker-compose.pi.yml` | minimal | qwen2.5:1.5b or :3b |
| **C. Pi archive-only** | Pi 4 + SSD | `docker-compose.pi-archive.yml` | any | none (no AI) |
| **D. Split** | Laptop (AI) + Pi (archive) | both, LAN | any | as fits laptop |

Pattern C and D model the "AI dies but archive survives" story: a stripped-down Pi running only kiwix-serve is a fully-functioning local library other devices on the LAN can read. The split deployment exposes `KIWIX_HOST=pi.local` to the RAG service.

The Pi compose file uses extended healthcheck timeouts (60s/120s vs 30s/90s on laptop) and caps Ollama's memory (`OLLAMA_MEMORY_LIMIT=4G`). These are tuned-from-experience numbers, not guesses.

---

## 7. Bundles (the content)

Three published bundles, each with a manifest (`bundles/<name>/manifest.json`) listing ZIM file, source URL, SHA-256, and license, plus a `LICENSE.md` inventory.

### Minimal — ~4.7 GB

- WikiMed (medical reference, CC-BY-SA 4.0) ~1.4 GB
- iFixit (repair guides, **CC-BY-NC-SA 3.0**) ~3.3 GB
- Recommended chat model: qwen2.5:3b. Index ~200 MB. Indexing ~5 min.

### Balanced — ~24 GB *(default)*

- Wikipedia English mini (full text, no images) ~12 GB
- WikiMed ~1.4 GB
- iFixit ~3.3 GB
- SuperUser / Unix-Linux / Ask Ubuntu Stack Exchange ~7.5 GB combined
- Recommended chat model: qwen2.5:7b. Index 1–2 GB. Indexing 15–30 min.

### Comprehensive — ~411 GB

- Wikipedia English **with images** ~115 GB
- WikiMed, iFixit
- Project Gutenberg English ~206 GB
- Stack Overflow 2023-11 snapshot ~75 GB
- Math Stack Exchange ~6.9 GB
- Recommended chat model: qwen2.5:7b (16 GB RAM) or qwen2.5:14b (32+ GB RAM). Indexing 2–4 hours.

### License posture

Every bundle's license inventory is checked into the repo. iFixit is **non-commercial only** — a real legal constraint to mention when discussing reuse. Wikipedia/WikiMed/Stack Exchange are CC-BY-SA (ShareAlike). Project Gutenberg is mostly public-domain in the US but text-by-text where it gets fuzzy.

---

## 8. The bootstrap experience

One command, by design: `./scripts/bootstrap.sh [--bundle balanced] [--pi] [--model qwen2.5:7b]`.

The script (~700 lines, well-instrumented) walks through:

1. **Prereqs** — Docker ≥ 24, curl, sha256sum, python3, Docker daemon up.
2. **Data dirs** — create `/var/lib/allarkive/{zim,index,models,data}` (or the Pi path), check write perms.
3. **Env file** — copy `.env.example`, require `WEBUI_SECRET_KEY` (64-char hex, generated via `openssl rand -hex 32`).
4. **Port detection** — find conflicts, auto-assign free ports, store choices back to `.env`.
5. **Disk-space check** — fail fast if the chosen bundle won't fit.
6. **Bundle fetch** — calls `fetch-bundle.sh`, downloads each ZIM with curl resume, **verifies SHA-256 against the manifest**, halts loudly on mismatch.
7. **Stack up** — `docker compose up -d`, wait for health checks. Detects an already-running Ollama on the host (e.g. macOS Ollama.app on `host.docker.internal:11434`) and reuses it.
8. **Pull models** — chat + embedding via Ollama API, with progress.
9. **Index** — `docker compose exec rag python indexer.py`, prints chunk counts per ZIM at the end.

The whole thing is idempotent and the resolved storage paths are persisted to `~/.config/allarkive/config.json` so subsequent runs pick them up automatically.

Lifecycle peers:
- `fetch-bundle.sh` — bundle download + checksum verification, standalone.
- `reindex.sh` — re-run the indexer after adding ZIMs.
- `teardown.sh` — stop the stack, preserve data.
- `cleanup.sh` — stop and optionally remove images / data / both, with prompts before destructive steps.

---

## 9. The landing page

`http://localhost:8080` is the deliberate front door. The landing page (`landing/index.html` + `app.js` + `style.css`, served by nginx) has three modes:

- **Search** — direct query against Kiwix's full-text index, opens the article.
- **Ask AI** — submits to `/api/rag/v1/chat/completions`, streams the response, renders inline citations linked back to the kiwix article.
- **Manage** — table of installed archives (name, size, last updated), with copyable instructions for adding/removing bundles.

Two pieces of mandatory text the project never lets you remove:

> **Responses can be wrong. Check the citations.** *(rendered with every AI answer)*
>
> AllArkive is a research and reference tool. It is not a substitute for professional medical, legal, or safety advice. *(footer)*

The visual aesthetic is library catalogue, not SaaS. System fonts only, no web fonts, no external CDN, dark mode via `prefers-color-scheme`, information-dense. The status line literally says "binding: localhost only" so the user can see at a glance that nothing's leaking outbound.

---

## 10. Design and tone — rules with teeth

`docs/DESIGN.md` is the tone constitution. Both for the talk and for any external writing, these are the rules:

**Allowed framing:**
- "An offline research assistant that runs on your own hardware."
- "Useful when your internet is fine. More useful when it isn't."
- "Censorship resistance, privacy, and educational access."
- "RAG with citations is checkable, not infallible."

**Forbidden framing:**
- "Survive the collapse of the internet."
- "When the grid goes down…"
- "Civilization-in-a-box" *(internal joke only, never public)*
- Prepper / bunker / doomsday / apocalypse register
- Replacement for the internet / doctor / lawyer / expert

**Voice rules:**
- Plain words over jargon ("local AI" not "edge inference").
- Em dashes without spaces: `word—word`.
- No exclamation marks. No emoji in README, landing page, or error messages.
- "We" is correct (Sam + Sham).
- Never claim more than RAG delivers.

These rules show up in commit-review and PR-review. Drift is treated as a bug.

---

## 11. Threat model — what this does and doesn't protect against

Lifted verbatim in structure from `docs/THREAT_MODEL.md`.

### Protects against (partially)

1. **ISP / connectivity outage.** Once installed, runs fully offline. Trade-off: snapshot ages.
2. **Cloud rug-pulls.** No third-party runtime dependency. Trade-off: still trusting upstream projects (Kiwix, Ollama) at install time; AGPL forks viable if they shift.
3. **Source-level censorship.** ZIM on disk = unreachable to censors. Trade-off: must acquire ZIM during an unblocked window or via sneakernet.
4. **Query surveillance.** No telemetry, no outbound calls, default `127.0.0.1`. Trade-off: LAN opt-in exposes traffic to the local network operator.
5. **Local-machine privacy.** Chat history in a local sqlite, your machine. Trade-off: unencrypted disk = anyone with physical access reads it.

### Does **not** protect against

- Targeted attacker with code execution on the box.
- Hallucinations (mitigated by citations + "no sources" path; not eliminated — user must check).
- Poisoned content in custom bundles.
- Supply-chain attacks on upstream ZIM mirrors *between* checksum pin and download.
- AllArkive itself being malicious — running our installer is running our code with user permissions. Mitigations: open source, AGPL-3.0, signed releases, signed git tags, eventual reproducible builds.
- ISP / network operator seeing AllArkive *installation* traffic.
- Physical seizure. Use full-disk encryption.
- Legal exposure for archive content in your jurisdiction.

### Default security posture

All services `127.0.0.1` only. Open WebUI auth disabled (correct on localhost, must be enabled before LAN exposure). Telemetry forced off in three places. The `RAG_API_KEY` env (default `"allarkive"`) is explicitly **not** a security boundary; it's there for client compatibility, not protection.

---

## 12. Roadmap

### v0.1 (May 2026, locked)

Single-machine docker-compose install • three bundles (minimal/balanced/comprehensive) • RAG with citation enforcement • landing page • install guides (laptop, server, macOS, Windows WSL2) • four deployment patterns • threat model + disclaimers • GitHub + Codeberg mirror • signed releases and tags • demo GIF in README.

### Explicitly out of scope for v0.1

Clustering, federation, mesh, IPFS, phone apps, hardened/airgap build, specialized medical/legal/agricultural bundles, bundle deltas, multi-language UI, multi-user accounts, cloud sync, telemetry, public-internet-facing default.

### v0.2 candidates

Bundle deltas (no more 50 GB re-downloads). Better RAG: hybrid search (vector + keyword), multi-language. First-run wizard. Pre-flight check script. Backup/restore. Documented LAN opt-in with reverse proxy + auth.

### v0.3+ ideas

Specialized bundles (medical, agricultural, software). Non-technical UX. Mesh/LAN federation. Phone-as-client. Hardened build. End-to-end reproducible builds. Formal security audit.

### Will never do

SaaS. Telemetry. VC funding. "Anonymous usage stats." Marketed as survival/medical/legal tool. Non-reproducible binaries. Proprietary bundled content.

---

## 13. State of play (as of writing)

From `CHANGELOG.md [Unreleased]` and `TODO.md`:

**Done:** repo skeleton, manual install, compose files, RAG pipeline, landing page, per-bundle LICENSE.md files, images pinned to SHA-256 digests, bundle manifests promoted to v1.0, install guides rewritten for docker-compose primary path, RAG↔Open WebUI integration wired, `THREAT_MODEL.md` finalized.

**Open:**
- Hands-on Pi validation: imaging a Pi, walking `pi-text-only.md` and `pi-archive-only.md` end-to-end, testing the split deployment.
- Screenshots for install guides (need a clean install pass).
- Demo GIF, signed release artifacts, talk dry-run.

The technical scaffolding is in; the remaining work is empirical (Pi hardware) and presentational (talk + GIF + signing).

---

## 14. Governance and contribution

- **Two-person maintainer model.** Single maintainer can merge typo/doc/dep/bug-fix changes. Two-maintainer sign-off required for: locked decisions in `CLAUDE.md`, default security posture, bundle contents, license/governance, minor/major releases.
- **No legal entity, no funding, no commercial relationships.**
- **DCO sign-off** on every commit (`git commit -s`). Not a CLA.
- **Conventional Commits** in imperative mood. Branch prefixes `feat/`, `fix/`, `docs/` from `dev`.
- **Releases:** semver; signed git tags; release notes + checksums + signed artifacts; mirror verified; ≥ one release per quarter.

What won't be accepted: telemetry of any kind, default-on remote access, floating image tags, bundled content with unclear licensing, runtime cloud dependencies, anything that erases citation disclaimers.

---

## 15. The deployment cheat sheet (one table)

| Aspect | Detail |
|---|---|
| Primary entry | `http://localhost:8080` (nginx landing) |
| Archive | `http://localhost:8081` (kiwix-serve) |
| Chat UI | `http://localhost:3000` (Open WebUI) |
| RAG API | `http://localhost:8000` (FastAPI, OpenAI-compatible) |
| LLM | `http://localhost:11434` (Ollama) |
| Default chat model | `qwen2.5:7b` |
| Default embed model | `nomic-embed-text` (768-dim) |
| Vector store | sqlite-vec, single file at `$DATA/index/index.db` |
| Chunking | 800 chars, 100 overlap, top-K=5, max L2 distance 1.0 |
| Config file | `~/.config/allarkive/config.json` |
| Min RAM (laptop) | 8 GB; 16 GB recommended |
| Min RAM (Pi) | 4 GB; 8 GB recommended |
| Disk (balanced bundle) | ~28 GB |
| License (glue) | AGPL-3.0 |
| Public debut | BSides Melbourne, 16–17 May 2026 |

---

## 16. Suggested narrative arcs

For a write-up or a talk, three arcs that the existing material already supports:

1. **"How to stop a local LLM from hallucinating."** Open with the RAG-refusal trick (no sources → API refuses, model is never called). Pull through to citations rendered as kiwix links. Show the chain end-to-end on stage. This is the strongest single technical story.
2. **"Resilience without doomsday."** Lead with the framing fight in `DESIGN.md` — why this is *not* prepper software, and why the maintainers police that line. Frame around real censorship events, ISP outages, cloud rug-pulls. Pi-archive-only as the closing demo: when the AI is gone, the library still works.
3. **"A 700-line bash script and five containers."** The build-it-yourself walkthrough. `bootstrap.sh` step by step, the four compose patterns, the bundle-and-checksum dance. Lands the "boring infrastructure" thesis: this is rentable as a weekend project for a determined sysadmin, and that's the point.

Any of the three can carry the BSides slot; mixing the first and second is probably the strongest combination for an infosec audience.
