# AllArkive

**A self-hostable, offline knowledge ark — Wikipedia, repair guides, books, and a local AI that can search them, all running on your own hardware.**

> Because the internet wasn't supposed to be rented.

---

## What this is

AllArkive bundles three things that already exist into something one person can install in an afternoon:

1. **An offline knowledge archive** — Wikipedia, Stack Exchange, Project Gutenberg, iFixit, and more, packaged as Kiwix ZIM files.
2. **A local AI** — an open-weight LLM (via Ollama and Open WebUI) that runs entirely on your machine, with no calls to the cloud.
3. **A retrieval pipeline** — RAG that lets the AI answer questions using the local archive, with citations back to the source.

Run it on a laptop, a home server, or a Raspberry Pi. Use it as a private research assistant. Keep it as a fallback for when the open web gets worse.

**Status**: alpha. v0.1 is the first public release. See [`ROADMAP.md`](ROADMAP.md).

## Why

The infrastructure of shared knowledge is more centralised, more surveilled, and more hostile to users than it has ever been. The tools to run a useful piece of it on cheap hardware exist — they just haven't been packaged together. We packaged them.

This is **not** a survival kit, a prepper bunker, or a doomsday cache. It's a library and a search tool, built on open weights and open content, that runs on your own machine. The framing is **censorship resistance, privacy, and educational access**.

## What's in the default bundle (v0.1)

The "balanced" bundle, recommended for most laptops (~23 GB ZIM total, ~28 GB with model):

- **Wikipedia** (English, mini — full text, minimal styling) — 12 GB
- **WikiMed** — medical reference, for general lookups, **not** medical advice
- **iFixit** — repair guides
- **SuperUser** — general tech Q&A

Smaller and larger bundles are documented in [`docs/bundles/`](docs/bundles/).
Project Gutenberg (full corpus, ~200 GB) is in the `comprehensive` bundle.

> The AI can be wrong. RAG with citations makes its output checkable, not infallible. **Not a substitute for professional medical, legal, or safety advice.**

## Install

```bash
git clone https://github.com/allarkive/allarkive.git
cd allarkive
cp compose/.env.example compose/.env
./scripts/bootstrap.sh
```

System requirements:
- **Minimum**: 8 GB RAM, 30 GB disk, x86_64 or arm64
- **Recommended**: 16 GB RAM, 50 GB SSD, modern CPU
- **Pi text-only build**: Raspberry Pi 4 (4 GB+) with USB SSD

After install, open `http://localhost:8080` for the landing page.

> **Heads-up: indexing runs after the stack starts and takes time.** The RAG indexer embeds every ZIM chunk through your local Ollama. On CPU this is **several hours for the balanced bundle**, less for minimal. Leave it running — it's resumable and idempotent. Kiwix browsing works immediately at `http://localhost:8081`; RAG answers in Open WebUI improve as coverage grows, so "no sources found" early on is expected for topics not yet indexed. Watch progress with `docker compose -f compose/docker-compose.yml logs -f rag`.

## Documentation

Pick your starting point:

| I want to… | Read this |
|---|---|
| Install on Linux (laptop or desktop) | [`docs/install/laptop.md`](docs/install/laptop.md) |
| Install on macOS | [`docs/install/macos.md`](docs/install/macos.md) |
| Install on Windows (WSL2) | [`docs/install/windows.md`](docs/install/windows.md) |
| Install on a headless server | [`docs/install/server.md`](docs/install/server.md) |
| Run on a Raspberry Pi (full stack) | [`docs/deployment/pi-text-only.md`](docs/deployment/pi-text-only.md) |
| Run a Pi as a dedicated archive node | [`docs/deployment/pi-archive-only.md`](docs/deployment/pi-archive-only.md) |
| Split the archive and AI across two machines | [`docs/deployment/split.md`](docs/deployment/split.md) |
| Enable LAN access for other devices | [`docs/deployment/lan-access.md`](docs/deployment/lan-access.md) |
| Choose a content bundle | [`docs/bundles/README.md`](docs/bundles/README.md) |
| Understand how it works | [`docs/ARCHITECTURE.MD`](docs/ARCHITECTURE.MD) |
| Understand what it protects against | [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md) |
| Contribute | [`CONTRIBUTING.md`](CONTRIBUTING.md) |
| See what's planned | [`ROADMAP.md`](ROADMAP.md) |
| See all docs | [`DOCS.md`](DOCS.md) |

## Scripts

| Script | What it does |
|--------|-------------|
| `scripts/bootstrap.sh` | First-run setup. Checks prerequisites, creates data directories, fetches a bundle, starts the Docker Compose stack, pulls both AI models, and runs the RAG indexer. Idempotent — safe to re-run. Accepts `--bundle`, `--pi`, `--zim-dir`, `--models-dir`, and other flags. |
| `scripts/fetch-bundle.sh` | Downloads a named bundle (`minimal`, `balanced`, or `comprehensive`). Verifies every ZIM file against its SHA-256 checksum and stops on any failure. Resumes interrupted downloads. |
| `scripts/teardown.sh` | Stops the Docker Compose stack. Mirrors `bootstrap.sh`'s compose-file selection — pass `--pi` or `--pi-archive` to stop the matching stack. Does not delete data. |
| `scripts/cleanup.sh` | Stops the stack and optionally removes images (`--images`), data directories (`--data`), or both (`--all`). Prompts before any destructive step. |

The `scripts/rag/` directory contains the RAG pipeline that runs inside Docker: `indexer.py` (ZIM → vector index), `server.py` (OpenAI-compatible API), `prompt.py` (citation-enforcing system prompt), and `citations.py` (post-process `[N]` markers into links). These are not meant to be run directly — the Compose stack manages them.

## Architecture

Three layers, each replaceable:

```
┌──────────────────────────────────────────┐
│  Glue: landing page, docker-compose,     │
│  bootstrap, RAG pipeline, docs           │
├──────────────────────────────────────────┤
│  Local AI: Ollama + Open WebUI + RAG     │
├──────────────────────────────────────────┤
│  Archive: Kiwix serving ZIM files        │
└──────────────────────────────────────────┘
```

Full breakdown: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).

## Security and threat model

- **Default-local binding.** Nothing listens on the public internet unless you opt in.
- **No telemetry.** Ever.
- **Signed releases.** Verify checksums for everything you download.
- **Honest disclaimers.** What this protects against and what it doesn't is documented in [`docs/THREAT_MODEL.md`](docs/THREAT_MODEL.md).

If you find a vulnerability, see [`SECURITY.md`](SECURITY.md).

## Contributing

We can't curate the world's knowledge alone. Read [`CONTRIBUTING.md`](CONTRIBUTING.md) and [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

Useful contributions include:
- Bundle proposals (a focused archive for a topic, language, or region)
- Install guides for OSes we don't cover
- RAG pipeline improvements
- Documentation, translations, and walkthroughs

You don't need to write code to be useful here.

## License

Glue code: **AGPL-3.0**. See [`LICENSE`](LICENSE).
Bundled content keeps its original licenses (Wikipedia is CC-BY-SA, Project Gutenberg is public domain, etc.). Each bundle ships with its own license inventory.

## Mirror

Primary: [github.com/allarkive/allarkive](https://github.com/allarkive/allarkive)
Mirror: [codeberg.org/allarkive/allarkive](https://codeberg.org/allarkive/allarkive)

## Credits

Built by Sam and Sham. Standing on the shoulders of [Kiwix](https://kiwix.org), [Ollama](https://ollama.com), [Open WebUI](https://openwebui.com), and the people who maintain the open archives we bundle.