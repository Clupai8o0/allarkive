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

The "balanced" bundle, recommended for most laptops (~28 GB ZIM total):

- **Wikipedia** (English, text-only) — ~22 GB
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

Full guide with screenshots: [`docs/install/`](docs/install/).

System requirements:
- **Minimum**: 8 GB RAM, 35 GB disk, x86_64 or arm64
- **Recommended**: 16 GB RAM, 50 GB SSD, modern CPU
- **Pi text-only build**: Raspberry Pi 4 (4 GB+) with USB SSD

After install, open `http://localhost:8080` for the landing page.

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