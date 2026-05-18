# ROADMAP

What ships when. The v0.1 scope is locked. Everything else is "interesting later."

## v0.1 — first public release (target: BSides Melbourne, May 16–17, 2026)

**Goal**: one person can install AllArkive on a laptop in an afternoon, ask the local AI a question about the local archive, and get an answer with citations they can verify.

### In scope
- `docker-compose` install of Kiwix + Ollama + Open WebUI on one machine.
- Default knowledge bundle (`balanced`) with English Wikipedia text-only, a medical reference wiki, iFixit, Project Gutenberg, Stack Exchange.
- Two additional bundles: `minimal` (Pi-friendly) and `comprehensive` (full Wikipedia with images for users with disk).
- RAG pipeline with citations. No-source = no-answer behaviour.
- Local landing page (search, chat, manage).
- Install guides for laptop, Linux server, macOS, Windows (via WSL2).
- Deployment patterns for Pi text-only, Pi archive-only, and laptop+Pi split.
- Threat model and explicit disclaimers.
- AGPL-3.0 licensed glue code; bundle content tracked with its own licenses.
- GitHub primary, Codeberg mirror.
- Signed releases, signed git tags.
- Demo GIF in README.

### Out of scope (explicitly deferred)
- Clustering, replication, federation between nodes.
- Mesh networking, serverless transport, IPFS-style content addressing.
- Phone apps (Android, iOS).
- Hardened or airgap-only build target.
- Specialised bundles for medical, agricultural, or legal use.
- Bundle deltas (incremental archive updates).
- Multi-language UI.
- Multi-user accounts / roles / quotas.
- Cloud sync of any kind.
- Telemetry of any kind.
- Public-internet-facing default deployment.

## v0.2 — quality of life

**Goal**: the install is smoother, the AI is better, the docs cover the long tail.

### Shipped (post-BSides 2026-05-18)
- **Improved RAG: better embeddings, hybrid search (vector + keyword).**
  Indexer rewritten with batched async embeddings (10–30× faster on CPU),
  int8 vector quantization (4× smaller vectors), offset-only chunk
  storage (~60% smaller index), and an opt-in Xapian/BM25 hybrid mode
  that skips dense indexing on multi-100-GB ZIMs entirely. Bundled
  under `RAG_PROFILE=pi|laptop|workstation` presets. See
  `docs/rag-optimization.md` and the `[Unreleased]` CHANGELOG entry.
- **Custom bundles.** `scripts/fetch-bundle.sh custom --add <url|handle>`
  lets users compose their own bundle from any ZIM on
  `download.kiwix.org` or a direct URL. Manifest is generated
  incrementally and gitignored. See `docs/bundles/README.md`.

### Candidates (not commitments)
- Bundle deltas — update an archive without re-downloading 50 GB.
- Pre-built index distribution — ship a vector index alongside the ZIM
  bundle so a Pi can skip indexing entirely. Feasibility validated in
  the v0.2 storage work; not yet wired into the release pipeline.
- Multi-language retrieval.
- A first-run wizard on the landing page (pick a bundle, pick a model).
- Pre-flight check script: "does your machine actually have what this needs."
- Backup and restore scripts for the archive and the user's chat history.
- Documented opt-in LAN access with reverse proxy + auth examples.

## v0.3+ — ideas

In rough order of how much they interest us, not how likely they are:

- **Specialised bundles**: a curated medical bundle (with extra disclaimers), an agricultural bundle (FAO docs, soil/crop guides), a software-development bundle (curated Stack Exchange + selected open-source docs).
- **A second landing-page experience for non-technical users** — bigger fonts, fewer options, more guidance.
- **Mesh / LAN federation** — multiple AllArkive nodes on the same LAN exchange archive availability so a query can hit any of them.
- **Phone-as-a-client app** — connect to a home AllArkive node from a phone on the same network. Not a full local stack on the phone.
- **Hardened build** — minimal base images, SELinux profiles, signed kernel modules, etc. For users who want this as part of a security posture.
- **Reproducible builds** end-to-end, including the model weights provenance chain.
- **A formal security audit** once the project has any users worth auditing for.

## What we will probably never do

- Become a hosted SaaS. The whole point is that it runs on your machine.
- Add tracking, telemetry, or "anonymous usage statistics."
- Take VC money for the core project.
- Promise this is a survival tool, a medical tool, or a legal tool. It isn't.
- Ship anything we can't reproduce from source.
- Bundle proprietary content.

## How to propose something for the roadmap

1. Read this doc and check it isn't already here under a different name.
2. Open an issue with the `roadmap` label.
3. Describe the user need, not the technical solution.
4. Note which version it might fit (v0.2, v0.3, "someday").
5. We'll discuss in the issue and either move it into a milestone or close with a reason.

Scope creep is the most likely way this project dies. We'd rather say no twenty times than ship a sprawl.