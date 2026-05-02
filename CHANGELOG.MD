# CHANGELOG

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
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