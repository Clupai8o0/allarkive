# CHANGELOG

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- `bundles/minimal/LICENSE.md`, `bundles/balanced/LICENSE.md`,
  `bundles/comprehensive/LICENSE.md` — per-bundle license summaries listing
  each ZIM's source, license, and attribution as required by CLAUDE.md.

### Changed
- All Docker images in `compose/docker-compose.yml`,
  `compose/docker-compose.pi.yml`, and `compose/docker-compose.pi-archive.yml`
  are now pinned to SHA-256 digests (multi-arch manifest digests fetched via
  `docker buildx imagetools inspect`). Images affected: kiwix-serve 3.8.2,
  ollama 0.22.1, open-webui 0.9.2, nginx 1.27.3-alpine.
- Bundle manifests promoted from `"version": "draft"` to `"version": "1.0"`;
  ZIM selection finalised and model choices resolved:
  `minimal` → WikiMed + iFixit, qwen2.5:3b;
  `balanced` → Wikipedia text + WikiMed + iFixit + Gutenberg + SuperUser, qwen2.5:7b;
  `comprehensive` → adds Wikipedia with images + Stack Overflow + Math SE, qwen2.5:7b.


- `docs/install/laptop.md` — rewritten from Milestone 2 draft to use
  docker-compose as the primary install path; manual-install appendix note
  preserved.
- `docs/install/server.md` — headless Linux server install guide; covers
  Docker Engine install, SSH port forwarding for browser access, data
  directory setup, and systemd service unit.
- `docs/install/macos.md` — macOS install guide; covers Docker Desktop,
  Apple Silicon Metal acceleration, resource limits, and file-sharing
  permissions.
- `docs/install/windows.md` — Windows install guide via WSL2 + Docker
  Desktop; covers WSL2 install, memory configuration, filesystem performance
  notes, NVIDIA GPU passthrough, and Defender exclusions.
- `docs/bundles/README.md` — bundle reference: contents, ZIM sizes, license
  summary, how to add custom ZIMs, and indexing time estimates for each bundle.
- `docs/deployment/lan-access.md` — opt-in LAN access guide; Caddy and nginx
  reverse-proxy examples, basic auth setup, firewall rules, and security
  posture summary.
- `docs/THREAT_MODEL.md` — renamed from `THREAD_MODEL.MD` (filename typo
  fix); added build-learnings section covering: Open WebUI auth-off default,
  RAG "no sources" enforcement, Docker bridge isolation, RAG API key not being
  a security boundary, image digest pinning status, and iFixit commercial-use
  restriction.

### Changed
- `compose/docker-compose.pi-archive.yml` — archive-only compose stack for a
  dedicated Raspberry Pi kiwix node (deployment pattern C); single service
  with a `KIWIX_BIND` variable for toggling between loopback-only and LAN
  access without editing the compose file.
- `docs/deployment/pi-text-only.md` — full walkthrough for running the
  AllArkive stack (kiwix + Ollama + RAG + landing page) on a Raspberry Pi 4/5
  with a USB SSD; covers OS imaging, SSD mount, Docker install, bootstrap,
  smoke tests, and ARM/low-RAM troubleshooting.
- `docs/deployment/pi-archive-only.md` — walkthrough for a dedicated kiwix
  archive node on a Pi; covers LAN exposure, firewall rules, ZIM bundle
  download, and verification steps.
- `docs/deployment/split.md` — guide for the split topology: AI (Ollama + RAG)
  on a laptop, archive (kiwix) on a separate Pi; covers NFS mount, index copy
  alternatives, network configuration, and citation URL consistency.

### Changed
- `compose/docker-compose.pi.yml` — added `OPENAI_API_BASE_URLS` and
  `OPENAI_API_KEYS` to the `open-webui` service so `allarkive-rag` appears as
  a selectable model (matching the laptop stack); added `depends_on: rag`
  with `condition: service_healthy` to `open-webui`; added
  `condition: service_healthy` to `rag` and `landing` depends_on blocks;
  extended Ollama `start_period` to 90 s; changed default `CHAT_MODEL` from
  `qwen2.5:7b` to `qwen2.5:1.5b` to fit Pi 4 with 4 GB RAM; added model size
  guidance comment.


- `landing/index.html`, `landing/style.css`, `landing/app.js` — local landing page
  served at `http://localhost:8080`; single-page with Search/Chat and Manage sections;
  dark mode via `prefers-color-scheme`; no external assets; all system fonts.
- `landing/nginx.conf` — nginx config serving static files on port 8080; proxies
  `/api/rag/` to the RAG service so the browser makes same-origin API calls.
- `scripts/rag/server.py` — `/status` endpoint returning binding mode, installed
  archives (name, size, mtime), archive count and total size, chat/embed model
  names, and RAG index readiness; consumed by the landing page status line and
  Manage section.
- `compose/docker-compose.yml` — `landing` service (`nginx:1.27.3-alpine`) on
  `LANDING_PORT` (default 8080); depends on `rag` being healthy.
- `compose/docker-compose.pi.yml` — `rag` and `landing` services added, matching
  the laptop stack with Pi-appropriate timeouts and a lower `RAG_MAX_ARTICLES` cap.
- `compose/.env.example` — `LANDING_PORT=8080`.

- `scripts/rag/server.py` — FastAPI RAG service exposing an OpenAI-compatible
  `/v1/chat/completions` endpoint; every response is grounded in retrieved passages
  or refused with an explicit no-sources message; supports streaming via SSE.
- `scripts/rag/indexer.py` — CLI indexer that reads ZIM files via `libzim`, chunks
  article text, embeds with Ollama (`nomic-embed-text`), and stores normalised
  float32 vectors in an sqlite-vec index at `$ALLARKIVE_DATA_DIR/index/index.db`.
  Idempotent: re-run safely; skips unchanged ZIMs; `--force` to rebuild.
- `scripts/rag/prompt.py` — system prompt template requiring `[N]` citation markers
  and a hard refusal when no relevant passages are found.
- `scripts/rag/citations.py` — post-processor that rewrites `[N]` markers to
  Markdown links pointing at the local kiwix article viewer.
- `scripts/rag/Dockerfile` — multi-arch (`linux/amd64`, `linux/arm64`) Python 3.11
  image for the RAG service.
- `scripts/rag/requirements.txt` — pinned Python dependencies for the RAG service.
- `compose/docker-compose.yml` — RAG service (`allarkive-rag:0.1.0`) added to the
  default stack; Open WebUI wired to the RAG service via `OPENAI_API_BASE_URLS` so
  `allarkive-rag` appears as a selectable model alongside Ollama models.
- `compose/.env.example` — RAG tuning knobs: `EMBED_MODEL`, `CHAT_MODEL`,
  `RAG_TOP_K`, `RAG_MAX_DISTANCE`, `RAG_MAX_ARTICLES`, `KIWIX_PUBLIC_URL`.
- `scripts/bootstrap.sh` — pulls `nomic-embed-text` embedding model and runs the
  indexer automatically on first boot.

### Changed
- `compose/docker-compose.yml` — `open-webui` now depends on `rag` being healthy
  before starting, ensuring the model is visible at first launch.
- `scripts/bootstrap.sh` — summary screen shows RAG port and re-index instructions.
- `docs/ARCHITECTURE.md` — filled in Milestone 4 decisions (vector DB, embedding
  model, Open WebUI integration approach).
- `TODO.md` — Milestone 4 CC tasks marked done; vector DB and embedding model open
  questions resolved.

- `compose/docker-compose.yml` — default stack with kiwix-serve, Ollama, and
  Open WebUI; all services bound to 127.0.0.1; CPU-only by default with a
  `--profile gpu` opt-in for NVIDIA GPU acceleration; telemetry disabled on
  Open WebUI; health checks on every service.
- `compose/docker-compose.pi.yml` — Raspberry Pi variant (deployment pattern B);
  data root defaults to `/mnt/ssd/allarkive`; extended healthcheck grace periods;
  Ollama memory cap via `OLLAMA_MEMORY_LIMIT`.
- `compose/.env.example` — documented environment template covering ports, data
  directory, Open WebUI secret key, and Pi overrides.
- `scripts/bootstrap.sh` — first-run setup: checks prerequisites, creates data
  directories, fetches the default bundle, starts the compose stack, and pulls
  the default Ollama model with streamed progress.
- `scripts/fetch-bundle.sh` — downloads and SHA-256 verifies ZIM files listed
  in a bundle manifest; resumes partial downloads; pins new checksums back to the
  manifest after first verification.
- `bundles/balanced/manifest.json` — draft balanced bundle: Wikipedia EN nopic,
  WikiMed, iFixit, Project Gutenberg, SuperUser (~30 GB total ZIMs).
- `bundles/minimal/manifest.json` — draft minimal bundle: WikiMed + iFixit
  (~3.5 GB total ZIMs; Pi-friendly).
- `bundles/comprehensive/manifest.json` — draft comprehensive bundle: Wikipedia
  EN with images, WikiMed, iFixit, Gutenberg, Stack Overflow, SuperUser, Math SE
  (~130 GB+ total ZIMs).
- `docs/install/laptop.md` — manual install guide (draft v0) covering Ollama,
  Kiwix, and Open WebUI on Ubuntu 22.04/24.04 LTS; includes smoke tests, port
  summary, and troubleshooting. To be validated and corrected during Milestone 2.
- Initial repository scaffolding.
- `CLAUDE.md` master instructions for agent-driven development.
- `ARCHITECTURE.md` describing the three-layer design.
- `DESIGN.md` covering tone, voice, and landing page direction.
- `THREAT_MODEL.md` documenting what the project does and does not protect against.
- `ROADMAP.md` separating v0.1 scope from v0.2+ ideas.
- `TODO.md`, `DOCS.md`, `GOVERNANCE.md`.
- `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`.
- `LICENSE` — AGPL-3.0 full text.
- `.gitignore` covering Python, Node, Docker, OS clutter, and ZIM archives.
- `.editorconfig` with per-filetype indent and line-ending rules.
- `.github/workflows/ci.yml` — markdown lint, shellcheck, compose validation, Python lint.
- `.github/workflows/mirror-codeberg.yml` — push mirror to Codeberg on every `main` commit.
- `.github/ISSUE_TEMPLATE/` — bug, feature, and bundle-proposal templates.
- `.github/PULL_REQUEST_TEMPLATE.md`.
- Directory skeleton: `compose/`, `scripts/rag/`, `bundles/`, `landing/`, `docs/install/`, `docs/bundles/`, `docs/deployment/`.
- License rationale paragraph in `CONTRIBUTING.md` — documents why AGPL-3.0 was chosen over MIT/Apache-2.0.

### Changed
- _Nothing yet._

### Deprecated
- _Nothing yet._

### Removed
- _Nothing yet._

### Fixed
- _Nothing yet._

### Security
- _Nothing yet._

---

## [0.1.0] — Unreleased

First public release. Scope:

- One-command Docker install of Kiwix, Ollama, and Open WebUI.
- Default starter knowledge bundle (English Wikipedia text-only, a medical reference wiki, iFixit, Project Gutenberg).
- RAG pipeline with citation-required prompts.
- Local landing page (search archive, chat with AI, manage bundles).
- Documentation: install guides for laptop and server; deployment patterns for Pi text-only, Pi archive-only, and split.
- Demo GIF in the README.
- Codeberg mirror automated via GitHub Action.
- AGPL-3.0 licensed glue code; bundled content keeps original licenses.

---

[Unreleased]: https://github.com/allarkive/allarkive/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/allarkive/allarkive/releases/tag/v0.1.0