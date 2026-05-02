# TODO.md

v0.1 task list. Updated as work happens. If a task is no longer needed, strike it through with an explanation rather than deleting it.

**Owner key**: `[S]` Sam, `[Sh]` Sham, `[E]` either, `[CC]` Claude Code.

## Milestone 1 — Repo skeleton

- [x] `[E]` Lock decisions in project brief
- [x] `[CC]` Create initial directory structure per `CLAUDE.md`
- [x] `[CC]` Add `LICENSE` (AGPL-3.0 full text)
- [x] `[CC]` Add `.gitignore` (Python, Node, Docker, OS clutter)
- [x] `[CC]` Add `.editorconfig`
- [x] `[CC]` Add `.github/workflows/ci.yml` — lint markdown, shellcheck scripts, validate compose
- [x] `[CC]` Add `.github/workflows/mirror-codeberg.yml` — push mirror on every commit to `main`
- [x] `[CC]` Add `.github/ISSUE_TEMPLATE/` — bug, feature, bundle proposal
- [x] `[CC]` Add `.github/PULL_REQUEST_TEMPLATE.md`
- [x] `[E]` Confirm AGPL-3.0 vs MIT one more time before merging LICENSE

## Milestone 2 — Manual install on Laptop 1

The first install is manual and notes-driven. Output is the first draft of `docs/install/laptop.md`.

- [ ] `[S]` Install Ollama on Laptop 1, pull recommended model, smoke test
- [ ] `[S]` Install Kiwix, fetch one small ZIM, serve it, smoke test
- [ ] `[S]` Install Open WebUI, point at Ollama, smoke test
- [ ] `[S]` Write up every step, every error, every confusion → `docs/install/laptop.md` v0
  _(CC created a starter draft; Sam fills in `____________` blanks and corrects wrong steps)_
- [ ] `[Sh]` Follow the draft on Laptop 2 from scratch, no questions to Sam
- [ ] `[Sh]` Every snag = a doc gap → file as issues
- [ ] `[E]` Resolve all install-doc issues; mark guide v1

## Milestone 3 — docker-compose

- [x] `[CC]` Draft `compose/docker-compose.yml` automating the manual steps
- [ ] `[CC]` Pin all images by digest, not tag
  _(version tags pinned: kiwix 3.8.2, ollama 0.22.1, open-webui 0.9.2;_
  _digest pinning requires `docker pull` + `docker inspect` — do this during Milestone 3 smoke test)_
- [x] `[CC]` Bind every service to `127.0.0.1` by default
- [x] `[CC]` `compose/.env.example` with placeholders
- [x] `[CC]` `scripts/bootstrap.sh` — pulls images, fetches default bundle, indexes, starts services
- [x] `[CC]` `scripts/fetch-bundle.sh` — downloads + SHA-256 verifies a named bundle
- [x] `[CC]` Bundle manifests: `bundles/minimal/manifest.json`, `bundles/balanced/manifest.json`, `bundles/comprehensive/manifest.json`
  _(draft manifests created; ZIM sha256 fields are empty — pin them after first download)_
- [ ] `[E]` Decide which ZIMs go in each bundle; capture decisions in bundle docs
- [ ] `[S]` Wipe Laptop 1, run `bootstrap.sh` end-to-end, fix what breaks

## Milestone 4 — RAG pipeline

- [ ] `[E]` Decide vector store (sqlite-vec vs lancedb vs qdrant) — see `ARCHITECTURE.md` open questions
- [ ] `[E]` Decide embedding model
- [ ] `[CC]` Build `scripts/rag/` — index ZIM content, expose retrieval API
- [ ] `[CC]` Prompt template: requires citations, refuses if no relevant passages
- [ ] `[CC]` Citation post-processing: rewrite to `kiwix://` links into the local archive viewer
- [ ] `[CC]` "No sources found" path tested
- [ ] `[CC]` Integrate with Open WebUI as a model proxy or function
- [ ] `[E]` Smoke test: 20 questions, manually verify citations are real and on-topic

## Milestone 5 — Landing page

- [ ] `[CC]` Static HTML/CSS/vanilla-JS landing page per `DESIGN.md`
- [ ] `[CC]` Three sections: Search, Chat, Manage
- [ ] `[CC]` Status line shows binding mode, archive size, model name
- [ ] `[CC]` Required disclaimer text (verbatim from `DESIGN.md`) in chat surface and footer
- [ ] `[CC]` Dark mode via `prefers-color-scheme`
- [ ] `[CC]` No external CDN; bundle every asset locally
- [ ] `[Sh]` UX review against `DESIGN.md`

## Milestone 6 — Pi targets

- [ ] `[E]` Image Pi 1 OS, attach USB SSD, mount at `/mnt/ssd`
- [ ] `[E]` Run `compose/docker-compose.pi.yml` (text-only, smaller model) on Pi 1
- [ ] `[E]` Document everything that breaks on ARM / low RAM → `docs/deployment/pi-text-only.md`
- [ ] `[E]` Image Pi 2 OS, attach USB SSD, install `kiwix-serve` only
- [ ] `[E]` Document the archive-only deployment → `docs/deployment/pi-archive-only.md`
- [ ] `[E]` Test the split deployment: AI on Laptop 1 talking to archive on Pi 2 → `docs/deployment/split.md`

## Milestone 7 — Documentation

- [ ] `[E]` Write `docs/install/laptop.md` (already drafted in Milestone 2)
- [ ] `[E]` Write `docs/install/server.md` (Linux server, no GUI)
- [ ] `[E]` Write `docs/install/macos.md`
- [ ] `[E]` Write `docs/install/windows.md` (WSL2 path)
- [ ] `[E]` Write `docs/bundles/README.md` — what each bundle contains, sizes, licenses
- [ ] `[E]` Write `docs/deployment/lan-access.md` — opt-in remote access with reverse proxy + auth
- [ ] `[E]` Fill out `THREAT_MODEL.md` with anything we learned during build
- [ ] `[E]` Add screenshots to install guides

## Milestone 8 — Soft-launch prep

- [ ] `[CC]` Record demo GIF on Laptop 1 (search → ask AI → click citation)
- [ ] `[E]` Sign and tag `v0.1.0`
- [ ] `[E]` Cut release with checksums and signed artifacts
- [ ] `[E]` Verify Codeberg mirror is live and current
- [ ] `[S]` BSides Melbourne talk dry run with Sham
- [ ] `[E]` Soft-launch to a few friends, collect feedback
- [ ] `[E]` HN post draft (do not post until talk lands)
- [ ] `[E]` Mastodon post draft

## Open questions (resolve before v0.1)

- Vector DB choice (see Milestone 4)
- Embedding model choice (see Milestone 4)
- Recommended model: Qwen 2.5 7B vs Llama 3.1 8B vs Mistral — pick one for the `balanced` bundle
- Default port for the landing page: `8080` works but conflicts with common dev tools — keep or change?
- DCO sign-off vs CLA — currently leaning DCO (see `CONTRIBUTING.md`)

## Out of scope (do not start)

If you're tempted, file in `ROADMAP.md` instead.

- Clustering, replication, mesh networking
- Phone apps
- Hardened/airgap-only build target
- Specialised medical or agricultural bundles
- Telemetry of any kind
- Public-internet-facing default deployment