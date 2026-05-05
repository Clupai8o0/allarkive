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

- [x] `[S]` Install Ollama on Laptop 1, pull recommended model, smoke test
- [x] `[S]` Install Kiwix, fetch one small ZIM, serve it, smoke test
- [x] `[S]` Install Open WebUI, point at Ollama, smoke test
- [ ] `[S]` Write up every step, every error, every confusion → `docs/install/laptop.md` v0
  _(CC created a starter draft; Sam fills in `____________` blanks and corrects wrong steps)_
- [ ] `[Sh]` Follow the draft on Laptop 2 from scratch, no questions to Sam
- [ ] `[Sh]` Every snag = a doc gap → file as issues
- [ ] `[E]` Resolve all install-doc issues; mark guide v1

## Milestone 3 — docker-compose

- [x] `[CC]` Draft `compose/docker-compose.yml` automating the manual steps
- [x] `[CC]` Pin all images by digest, not tag
  _(digests pinned via `docker buildx imagetools inspect`: kiwix, ollama, open-webui, nginx)_
- [x] `[CC]` Bind every service to `127.0.0.1` by default
- [x] `[CC]` `compose/.env.example` with placeholders
- [x] `[CC]` `scripts/bootstrap.sh` — pulls images, fetches default bundle, indexes, starts services
- [x] `[CC]` `scripts/fetch-bundle.sh` — downloads + SHA-256 verifies a named bundle
- [x] `[CC]` Bundle manifests: `bundles/minimal/manifest.json`, `bundles/balanced/manifest.json`, `bundles/comprehensive/manifest.json`
  _(ZIM sha256 fields are empty — pin them after first download)_
- [x] `[E]` Decide which ZIMs go in each bundle; capture decisions in bundle docs
  _(minimal: WikiMed + iFixit; balanced: Wikipedia text + WikiMed + iFixit + Gutenberg + SuperUser; comprehensive: adds Wikipedia with images + Stack Overflow + Math SE. LICENSE.md created for each bundle.)_
- [ ] `[S]` Wipe Laptop 1, run `bootstrap.sh` end-to-end, fix what breaks

## Milestone 4 — RAG pipeline

- [x] `[E]` Decide vector store → **sqlite-vec** (embedded, no extra service)
- [x] `[E]` Decide embedding model → **nomic-embed-text** via Ollama (768-dim)
- [x] `[CC]` Build `scripts/rag/` — index ZIM content, expose retrieval API
- [x] `[CC]` Prompt template: requires citations, refuses if no relevant passages
- [x] `[CC]` Citation post-processing: rewrite to kiwix links into the local archive viewer
- [x] `[CC]` "No sources found" path tested
- [x] `[CC]` Integrate with Open WebUI as a model proxy (OpenAI-compatible API on port 8000)
- [ ] `[E]` Smoke test: 20 questions, manually verify citations are real and on-topic

## Milestone 5 — Landing page

- [x] `[CC]` Static HTML/CSS/vanilla-JS landing page per `DESIGN.md`
- [x] `[CC]` Three sections: Search, Chat, Manage
- [x] `[CC]` Status line shows binding mode, archive size, model name
- [x] `[CC]` Required disclaimer text (verbatim from `DESIGN.md`) in chat surface and footer
- [x] `[CC]` Dark mode via `prefers-color-scheme`
- [x] `[CC]` No external CDN; bundle every asset locally
- [ ] `[Sh]` UX review against `DESIGN.md`

## Milestone 6 — Pi targets

- [ ] `[S]` Image Pi 1 OS, attach USB SSD, mount at `/mnt/ssd`
- [ ] `[S]` Run `compose/docker-compose.pi.yml` (text-only, smaller model) on Pi 1
  _(doc written; fix any gaps that appear during the actual run)_
- [ ] `[S]` Validate `docs/deployment/pi-text-only.md` — fill in timings, fix any wrong steps
- [ ] `[S]` Image Pi 2 OS, attach USB SSD, install `kiwix-serve` only
  _(use `compose/docker-compose.pi-archive.yml` + doc at `docs/deployment/pi-archive-only.md`)_
- [ ] `[S]` Validate `docs/deployment/pi-archive-only.md` during the actual Pi 2 setup
- [ ] `[S]` Test the split deployment: AI on Laptop 1 talking to archive on Pi 2
  _(follow `docs/deployment/split.md`; fix any gaps)_
- [x] `[CC]` Draft `docs/deployment/pi-text-only.md` — Pi 1 full walkthrough
- [x] `[CC]` Draft `docs/deployment/pi-archive-only.md` — Pi 2 kiwix-only walkthrough
- [x] `[CC]` Draft `docs/deployment/split.md` — split topology walkthrough
- [x] `[CC]` Create `compose/docker-compose.pi-archive.yml` — archive-only compose for Pi 2
- [x] `[CC]` Fix `compose/docker-compose.pi.yml` — add OPENAI_API_BASE_URLS to open-webui,
  add `depends_on: rag` with health condition, default CHAT_MODEL to `qwen2.5:1.5b`

## Milestone 7 — Documentation

- [x] `[CC]` Write `docs/install/laptop.md` (rewritten from Milestone 2 draft to use docker-compose)
- [x] `[CC]` Write `docs/install/server.md` (Linux server, no GUI)
- [x] `[CC]` Write `docs/install/macos.md`
- [x] `[CC]` Write `docs/install/windows.md` (WSL2 path)
- [x] `[CC]` Write `docs/bundles/README.md` — what each bundle contains, sizes, licenses
- [x] `[CC]` Write `docs/deployment/lan-access.md` — opt-in remote access with reverse proxy + auth
- [x] `[CC]` Fill out `THREAT_MODEL.md` with build learnings; fix filename typo (THREAD→THREAT)
- [ ] `[S]` Add screenshots to install guides _(requires a running install — do during Milestone 2 smoke test)_

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

- ~~Vector DB choice~~ → sqlite-vec (Milestone 4)
- ~~Embedding model choice~~ → nomic-embed-text (Milestone 4)
- ~~Recommended chat model~~ → **qwen2.5:7b** for `balanced` and `comprehensive` (better instruction following and multilingual capability vs Llama 3.1 8B and Mistral 7B); **qwen2.5:3b** for `minimal` (fits 4 GB Pi)
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