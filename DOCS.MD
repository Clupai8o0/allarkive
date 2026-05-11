# DOCS

Index of every documentation file in this repository. If a doc isn't here, it doesn't exist yet.

## How to use this index

If you're a **user**, start with `README.md`, then `docs/install/`.
If you're a **contributor**, read `CONTRIBUTING.md`, then `CLAUDE.md` (yes, even if you're not Claude — it's the project's working manual).
If you're an **agent** (Claude Code or otherwise), `CLAUDE.md` is mandatory.
If you're **evaluating the project's trustworthiness**, read `THREAT_MODEL.md`, `SECURITY.md`, and `GOVERNANCE.md`.

## Root-level docs

| File | Audience | Purpose |
|---|---|---|
| `README.md` | Public | One-line pitch, install snippet, "what's inside," license, status. The repo's front door. |
| `CLAUDE.md` | Agent / contributor | Master working instructions. Conventions, locked decisions, "always/never" rules. |
| `LICENSE` | Public | AGPL-3.0 full text. |
| `CHANGELOG.md` | Public / contributor | Versioned changes in [Keep a Changelog](https://keepachangelog.com) format. |
| `CONTRIBUTING.md` | Contributor | How to contribute code, content, docs. DCO sign-off, PR checklist. |
| `CODE_OF_CONDUCT.md` | Community | Contributor Covenant 2.1. |
| `SECURITY.md` | Security researchers | How to report vulnerabilities. |
| `GOVERNANCE.md` | Contributor | How decisions get made; maintainer process. |
| `ROADMAP.md` | Public / contributor | What's in v0.1, what's deferred, what we'll never build. |
| `TODO.md` | Maintainer / agent | Live task list for v0.1. |
| `DOCS.md` | Anyone | This file — index of every doc. |

## `docs/` — the deeper documentation

### Architecture and design

| File | Purpose |
|---|---|
| `docs/ARCHITECTURE.md` | The three-layer design, components, data flow, deployment patterns, storage layout, network topology. |
| `docs/DESIGN.md` | Tone, voice, UX principles, landing page direction, naming conventions, required disclaimer text. |
| `docs/THREAT_MODEL.md` | What the project does and does not protect against. Disclaimers. |

### Install guides (`docs/install/`)

| File | Purpose |
|---|---|
| `docs/install/laptop.md` | Default install on a laptop. The reference guide. |
| `docs/install/server.md` | Linux server, no GUI. |
| `docs/install/macos.md` | macOS-specific gotchas. |
| `docs/install/windows.md` | Windows via WSL2. |

### Bundle docs (`docs/bundles/`)

| File | Purpose |
|---|---|
| `docs/bundles/README.md` | What each default bundle contains, sizes, licenses. |
| `docs/bundles/minimal.md` | Pi-friendly text-only bundle. |
| `docs/bundles/balanced.md` | Default bundle for most laptops. |
| `docs/bundles/comprehensive.md` | Full Wikipedia with images plus extras. |
| `docs/bundles/custom.md` | How to build your own bundle. License checklist included. |

### Deployment patterns (`docs/deployment/`)

| File | Purpose |
|---|---|
| `docs/deployment/laptop.md` | Single-machine, all three layers (default). |
| `docs/deployment/pi-text-only.md` | Pi with smaller model and text-only bundle. |
| `docs/deployment/pi-archive-only.md` | Pi running just `kiwix-serve`, no AI. |
| `docs/deployment/split.md` | AI on one machine, archive on another, LAN-only. |
| `docs/deployment/lan-access.md` | Opt-in LAN access with reverse proxy + auth. |

### Security (`docs/security/`)

| File | Purpose |
|---|---|
| `docs/security/pgp-keys.txt` | Public PGP keys for release signing and security disclosure. |
| `docs/security/release-verification.md` | How to verify a release came from us. |

### Operating the project (`docs/ops/`)

| File | Purpose |
|---|---|
| `docs/ops/release.md` | Step-by-step release process for maintainers. |
| `docs/ops/mirror.md` | How the GitHub → Codeberg mirror works. |
| `docs/ops/incident-response.md` | What to do when something goes wrong publicly. |

### Talk and launch (`docs/talk/`)

Internal-ish, but kept in the public repo because the talk is part of the launch.

| File | Purpose |
|---|---|
| `docs/talk/abstract.md` | BSides Melbourne 2026 talk abstract. |
| `docs/talk/outline.md` | Talk structure and timing. |
| `docs/talk/qa-prep.md` | Anticipated questions and our answers. |
| `docs/talk/demo-script.md` | What we run on stage and what we say while it runs. |

## Status of each doc

| Doc | Status |
|---|---|
| `README.md` | ✅ written |
| `CLAUDE.md` | ✅ written |
| `LICENSE` | ✅ AGPL-3.0 full text |
| `CHANGELOG.md` | ✅ written (living doc) |
| `CONTRIBUTING.md` | ✅ written |
| `CODE_OF_CONDUCT.md` | ✅ written |
| `SECURITY.md` | ✅ written |
| `GOVERNANCE.md` | ✅ written |
| `ROADMAP.md` | ✅ written |
| `TODO.md` | ✅ written (living doc) |
| `DOCS.md` | ✅ this file |
| `docs/ARCHITECTURE.MD` | ✅ written |
| `docs/DESIGN.MD` | ✅ written |
| `docs/THREAT_MODEL.md` | ✅ written |
| `docs/install/laptop.md` | ✅ written |
| `docs/install/server.md` | ✅ written |
| `docs/install/macos.md` | ✅ written |
| `docs/install/windows.md` | ✅ written |
| `docs/bundles/README.md` | ✅ written |
| `docs/deployment/laptop.md` | ⬜ to write (single-machine default; laptop.md install guide covers it) |
| `docs/deployment/pi-text-only.md` | ✅ written |
| `docs/deployment/pi-archive-only.md` | ✅ written |
| `docs/deployment/split.md` | ✅ written |
| `docs/deployment/lan-access.md` | ✅ written |
| `docs/security/*` | ⬜ to write |
| `docs/ops/*` | ⬜ to write |
| `docs/talk/*` | ⬜ to write (alongside slide prep) |

## Updating this index

Any PR that adds a new doc must update the relevant table in this file in the same PR. CI will not enforce that — it's a maintainer responsibility.