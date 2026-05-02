# CHANGELOG

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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