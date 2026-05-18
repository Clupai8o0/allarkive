# CLAUDE.md

Master instructions for Claude Code working in this repository. Read this first, every session.

## What this project is

**AllArkive** is a self-hostable, open-source knowledge ark: offline knowledge archives (Kiwix/ZIM) plus a local LLM (Ollama + Open WebUI) plus retrieval-augmented generation (RAG) with citations. Runs on home-lab hardware. Open source under AGPL-3.0 for the glue code.

The pitch in one line: **a private, offline research assistant that runs on your own hardware, with citations you can check.**

Co-built and co-presented by Sam and Sham. Soft-launches alongside a BSides Melbourne talk on May 16–17, 2026.

## Read these in order

1. This file (`CLAUDE.md`) — conventions and rules
2. `ARCHITECTURE.md` — what we're building, structurally
3. `ROADMAP.md` — what's in v0.1, what's deferred
4. `TODO.md` — what to do next
5. `DESIGN.md` — tone, UX, landing page direction
6. `THREAT_MODEL.md` — what this project does and does not protect against
7. `DOCS.md` — index of every doc in the repo

## Locked decisions — do not relitigate

These are settled. If a change feels needed, raise it in an issue, do not silently drift.

- **Three-layer architecture**: archive (Kiwix/ZIM) → local AI (Ollama + Open WebUI + RAG) → glue (docker-compose, scripts, landing page, docs).
- **v0.1 scope was locked at BSides 2026-05-16/17**. Active dev is v0.2 (post-launch quality of life) — see `ROADMAP.md` for what's `Shipped` vs `Candidates`. Out of scope across near-term versions: clustering, mesh networking, phone apps, hardened security builds, specialised medical/agricultural bundles.
- **RAG schema is versioned** (`meta.schema_version` in `index.db`). Current is **2** (offset-only chunk storage, int8 vectors by default, profile-driven config, opt-in BM25 hybrid). Server refuses to start on mismatch. Bumping it means a forced reindex — never an in-place migration. Bump `EXTRACTOR_VERSION` in `scripts/rag/textproc.py` if you change the HTML→text extractor in a way that shifts byte offsets.
- **RAG profile system**: `RAG_PROFILE=pi|laptop|workstation` is the canonical knob. Individual `RAG_*` env vars override the preset. New tuning options should be added to `scripts/rag/profiles.py` as fields on the preset, not as one-off env vars. See `docs/rag-optimization.md`.
- **License**: AGPL-3.0 for the glue code (this repo). Bundled content keeps its own licenses (Wikipedia CC-BY-SA, Project Gutenberg public domain, etc.). Track every bundle's license in `bundles/<name>/LICENSE.md`.
- **Hosting**: GitHub primary, Codeberg mirror via GitHub Action.
- **Default network binding**: localhost only. Remote access is opt-in and requires documented reverse-proxy + auth setup.
- **Tone**: dry, practical, resilience-framed. Public framing is **censorship resistance, privacy, educational access**. Not apocalypse, not prepper, not survival.
- **Honesty about RAG**: citations make the model checkable, not infallible. Every UI surface that shows model output also shows sources. Disclaimers are explicit, not buried.
- **Hardware targets for v0.1**: 2 laptops (main dev + independent install) and 2 Raspberry Pis on USB SSDs (one text-only build, one archive-only node). No SD cards for the archive — known failure mode.

## Always do

- Read `TODO.md` before starting work; update it as you go.
- Update `CHANGELOG.md` under `[Unreleased]` for every user-visible change.
- Write commits as conventional commits (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`).
- Add a `Signed-off-by` line to every commit (Developer Certificate of Origin — see `CONTRIBUTING.md`).
- Default-bind services to `127.0.0.1` in compose files. Document the remote-access opt-in path separately.
- Pin every dependency to a version (image tags, model versions, package versions). Floating tags are forbidden.
- Verify checksums for any ZIM file or model download. Surface verification failures loudly.
- Cite sources in any RAG response — no answer without sources.
- Keep secrets out of the repo. Use `.env.example` with placeholders only.
- Test on Laptop 1 (main dev), then have someone follow the install guide on Laptop 2 from scratch. Every snag = a doc gap to fix.

## Never do

- Don't add features outside the v0.1 scope in `ROADMAP.md`. If it feels essential, it goes on the v0.2+ list with a note.
- Don't push doomsday or survival framing into copy, error messages, README, or the landing page. See `DESIGN.md` for tone rules.
- Don't market this as medical, legal, or survival advice. Disclaimers must be explicit.
- Don't ship binaries we can't reproduce from source. Prefer published source over pre-built artifacts.
- Don't enable telemetry. Anywhere. Period.
- Don't bundle content without a license check.
- Don't expose any service to the public internet by default. No exceptions.
- Don't use floating image tags (`:latest`). Pin everything.
- Don't generate slide visuals or visual mockups in this repo unless explicitly asked.
- Don't write copy that erases Sham. "We" is correct here.

## Repository layout (target)

```
.
├── CLAUDE.md                    # this file
├── README.md                    # public-facing intro
├── LICENSE                      # AGPL-3.0
├── CHANGELOG.md
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── SECURITY.md
├── GOVERNANCE.md
├── ROADMAP.md
├── TODO.md
├── DOCS.md                      # docs index
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DESIGN.md
│   ├── THREAT_MODEL.md
│   ├── install/                 # OS-specific install guides
│   ├── bundles/                 # bundle docs
│   └── deployment/              # deployment patterns (laptop, pi-text, pi-archive)
├── compose/
│   ├── docker-compose.yml       # default stack
│   ├── docker-compose.pi.yml    # ARM / low-RAM variant
│   └── .env.example
├── scripts/
│   ├── bootstrap.sh             # one-command install
│   ├── fetch-bundle.sh          # download + verify a bundle
│   └── rag/                     # RAG pipeline
├── bundles/
│   ├── minimal/manifest.json    # name, ZIMs, checksums, licenses
│   ├── balanced/manifest.json
│   └── comprehensive/manifest.json
├── landing/                     # local landing page (static)
└── .github/
    ├── workflows/
    │   ├── ci.yml
    │   └── mirror-codeberg.yml
    ├── ISSUE_TEMPLATE/
    └── PULL_REQUEST_TEMPLATE.md
```

If you create a new top-level directory, document it here in the same PR.

## Conventions

### Code style
- **Shell**: POSIX where possible, otherwise Bash with `set -euo pipefail`. Run `shellcheck` on every script.
- **Python** (RAG glue): 3.11+, formatted with `ruff format`, linted with `ruff check`. Type hints required.
- **YAML**: 2-space indent, no tabs.
- **Markdown**: headings ATX-style (`#`), 80-col soft wrap, em dashes without spaces (`word—word`).

### Commit messages
Conventional commits, imperative mood, present tense.
```
feat(rag): add citation-aware retrieval over ZIM index
fix(compose): bind ollama to 127.0.0.1 by default
docs(install): add Pi text-only walkthrough
```
Every commit ends with `Signed-off-by: Name <email>`.

### Branches
- `main` — releasable
- `dev` — integration
- `feat/<short-name>` — features
- `fix/<short-name>` — fixes
- `docs/<short-name>` — docs

### Releases
- Semver: `v0.1.0`, `v0.1.1`, etc.
- Signed git tags. Signed release artifacts.
- `CHANGELOG.md` updated and `[Unreleased]` cleared on every release.

## Working with the agent (you)

- **Scope discipline**: if asked to do something outside v0.1, push back. Cite `ROADMAP.md`.
- **Doc-first changes**: if behavior changes, the doc changes in the same PR.
- **No silent decisions**: anything that changes a locked decision needs an issue and explicit sign-off from Sam.
- **Ask when unclear**: better to ask than guess. Sam decides on scope; Sham co-decides on UX and bundle contents.

## Demo and talk context

- BSides Melbourne, May 16–17, 2026.
- Audience: infosec, skeptical, allergic to hype.
- Demo target: Laptop 1, full stack, screen recording or GIF in the README.
- Q&A prep lives in the talk repo (separate), not here.

## When something breaks

1. Check `docs/install/` for the platform you're on.
2. If it's a fresh class of failure, file an issue with the install-log excerpt.
3. If it's a bug in our scripts, fix it and add a regression note to `CHANGELOG.md`.
4. If it's upstream (Kiwix, Ollama, Open WebUI), document the workaround and link to the upstream issue.

---

If anything in this file conflicts with another doc, this file wins. If anything here conflicts with reality, fix this file.