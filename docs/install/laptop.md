# Installing AllArkive on a laptop

> **Status**: v1 — docker-compose install path. The manual-install notes from
> Milestone 2 are preserved in the appendix for reference.

This guide installs AllArkive on a laptop running Linux (Ubuntu 22.04 LTS
or 24.04 LTS), using the docker-compose stack. For macOS see
`docs/install/macos.md`. For Windows see `docs/install/windows.md`.

**Time estimate**: 15–30 minutes setup, then waiting for downloads (depends
on your internet connection and which bundle you choose). After the stack
starts, RAG indexing runs in the background — **expect several hours for the
balanced bundle on CPU**. See *Indexing takes hours* below.

---

## Quick start (automated)

If you just want everything running with one command, use `bootstrap.sh`.
It handles directory creation, bundle download, image build, model pull,
and indexing automatically:

```bash
git clone https://github.com/Clupai8o0/allarkive.git
cd allarkive
cp compose/.env.example compose/.env
# Generate and paste a secret key:
openssl rand -hex 32  # copy this output into WEBUI_SECRET_KEY= in compose/.env
nano compose/.env
# Then run everything:
./scripts/bootstrap.sh --bundle balanced
```

The manual steps below are equivalent — follow them if you want more control
or need to debug a specific step.

### Indexing takes hours — leave it running

When `bootstrap.sh` finishes, the **RAG indexer keeps running** in the
`rag` container, embedding every ZIM chunk through your local Ollama. On CPU
this is the slowest part of setup:

- **minimal bundle**: 10–30 minutes
- **balanced bundle**: several hours
- **comprehensive bundle**: tens of hours, plan overnight

The indexer is **resumable and idempotent** — you can close the terminal,
suspend the laptop, or reboot, and re-running `bootstrap.sh` (or
`docker compose exec rag python indexer.py`) picks up where it left off.

Kiwix browsing at `http://localhost:8081` works **immediately**. RAG answers
in Open WebUI improve as coverage grows — "no sources found" early on is
expected for topics not yet indexed. Watch progress:

```bash
docker compose -f compose/docker-compose.yml logs -f rag
```

If indexing feels too slow, coverage seems incomplete, or something errors —
see [`docs/TROUBLESHOOTING.md`](../TROUBLESHOOTING.md). Covers cap/coverage
tuning (`--max-articles`, `--full-index`), embedding speed on different
hardware, common sqlite-vec errors, and re-running bootstrap to expand
coverage without losing existing work.

---

## Prerequisites

### Hardware

| | Minimum | Recommended |
|-|---------|-------------|
| RAM | 8 GB | 16 GB |
| Free disk | 10 GB (minimal bundle + model) | 30 GB (balanced bundle + model) |
| CPU | Any x86_64 | More cores = faster inference |
| GPU | Not required | CUDA GPU detected automatically |

### Software

- **Docker Engine 24+** with the Compose plugin. Test with:
  ```bash
  docker compose version
  ```
  If missing, install from the [official Docker docs](https://docs.docker.com/engine/install/).
  Do **not** use the distro-packaged `docker.io` — it may be too old.

- `curl`, `git`, `openssl` (standard on most Ubuntu installs)

---

## Step 1: Clone the repository

```bash
git clone https://github.com/Clupai8o0/allarkive.git
cd allarkive
```

---

## Step 2: Set up configuration

Copy the example environment file and fill in the required values:

```bash
cp compose/.env.example compose/.env
```

Generate a secret key for Open WebUI session signing:

```bash
openssl rand -hex 32
```

Open `compose/.env` and paste the result into `WEBUI_SECRET_KEY=`.

That is the only required change. Review the rest of the file if you want to
change ports, the data directory, or the default model, but the defaults work.

---

## Step 3: Create data directories

All ZIM files, models, the RAG index, and Open WebUI's database live under
one root. Create it once:

```bash
sudo mkdir -p /var/lib/allarkive/{zim,index,models,data}
sudo chown -R "$USER" /var/lib/allarkive
```

If your laptop has limited disk on `/var/`, change `ALLARKIVE_DATA_DIR` in
`compose/.env` to a path with more space (e.g. an external drive mounted
at `/mnt/external/allarkive`).

---

## Step 4: Fetch a bundle

A bundle is a curated set of ZIM files. Choose one:

| Bundle | Contents | Disk (ZIMs only) | Good for |
|--------|----------|-----------------|----------|
| `minimal` | WikiMed + iFixit | ~4 GB | Low-disk test run |
| `balanced` | Wikipedia (mini) + WikiMed + iFixit + SuperUser + Unix SE + Ask Ubuntu | ~23 GB | Daily use |
| `comprehensive` | Full Wikipedia (images) + Gutenberg + Stack Exchange | ~330 GB | Large-disk machines |

Download and verify:

```bash
./scripts/fetch-bundle.sh balanced
```

The script downloads each ZIM file and verifies its SHA-256 checksum. If
verification fails, it stops and tells you which file is corrupt. Do not
proceed past a checksum failure — re-run or re-download.

---

## Step 5: Start the stack

```bash
cd compose/
docker compose up -d
```

On first run, Docker does two things before the services start:

1. **Builds the RAG image from source** (`scripts/rag/`) — takes 2–4 minutes
   depending on your machine and network (downloads Python dependencies).
2. **Pulls the remaining images** (kiwix-serve, Ollama, Open WebUI, nginx).

Subsequent starts are fast — images are already present.

To watch progress:

```bash
docker compose logs -f
```

Wait until all containers show `healthy`:

```bash
docker compose ps
```

Typically 2–5 minutes on first run (excluding model download), less than a
minute on subsequent starts.

### GPU acceleration (optional)

If your laptop has an NVIDIA GPU with CUDA drivers installed:

```bash
docker compose --profile gpu up -d
```

---

## Step 6: Pull AI models

Two models are needed — the chat model (for answering questions) and the
embedding model (for indexing and search). Pull them before indexing:

```bash
# Chat model (~4 GB for qwen2.5:7b):
docker compose exec ollama ollama pull qwen2.5:7b

# Embedding model (~270 MB):
docker compose exec ollama ollama pull nomic-embed-text
```

If you chose a different model in `compose/.env`, substitute it here.
Both pulls resume automatically if interrupted.

---

## Step 7: Index the archive

The RAG pipeline indexes your ZIM files so the AI can search them. Trigger
it manually so you can watch the output:

```bash
docker compose exec rag python indexer.py \
    --zim-dir /data \
    --index-dir /index \
    --ollama-url http://ollama:11434
```

To force a full rebuild of an existing index:

```bash
docker compose exec rag python indexer.py \
    --zim-dir /data \
    --index-dir /index \
    --ollama-url http://ollama:11434 \
    --force
```

Indexing time depends on the bundle and hardware. The balanced bundle takes
roughly 10–30 minutes on a modern laptop. The index persists across restarts;
you only need to re-index if you add or change ZIM files.

---

## Step 8: Open the landing page

Open `http://localhost:8080` in a browser.

You should see the AllArkive landing page with a status line showing your
archive size and model name. Try:

1. **Search the archive** — full-text search over your ZIM files via Kiwix.
2. **Ask the AI** — type a question and see the answer with numbered citations
   linking back to the archive.

---

## Port summary

All ports are bound to `127.0.0.1` (loopback only) by default. Nothing
is reachable from outside your machine.

| Service | Port | Bound to |
|---------|------|----------|
| Landing page | 8080 | 127.0.0.1 |
| kiwix-serve | 8081 | 127.0.0.1 |
| Open WebUI | 3000 | 127.0.0.1 |
| Ollama | 11434 | 127.0.0.1 |
| RAG service | 8000 | 127.0.0.1 |

To change a port, edit `compose/.env`.

---

## Stopping and restarting

```bash
# Stop without removing volumes:
cd compose/ && docker compose down

# Start again (fast, model already downloaded):
cd compose/ && docker compose up -d
```

---

## Cleanup and uninstall

Use `scripts/cleanup.sh`. It has three levels — nothing is deleted unless
you explicitly ask.

| Command | What it removes |
|---------|----------------|
| `./scripts/cleanup.sh` | Stops and removes containers only. Data and images kept. |
| `./scripts/cleanup.sh --images` | Also removes Docker images (re-pulled on next start). |
| `./scripts/cleanup.sh --data` | Also deletes the data directory: ZIMs, models, RAG index, Open WebUI DB. **Irreversible.** Prompts before deleting. |
| `./scripts/cleanup.sh --all` | `--images` + `--data`. Full wipe. Prompts before deleting. |

After a full wipe, start fresh with `./scripts/bootstrap.sh --bundle balanced`.

---

## Updating

Pull new images, then restart:

```bash
cd compose/
docker compose pull
docker compose up -d
```

Check `CHANGELOG.md` before updating to see if any config or data migration
is needed.

---

## Troubleshooting

### `docker compose` command not found

Install the Docker Compose plugin: `sudo apt install docker-compose-plugin`.

### `WEBUI_SECRET_KEY` error on startup

The key is required. Run `openssl rand -hex 32`, paste the result into
`compose/.env` as `WEBUI_SECRET_KEY=<value>`.

### Open WebUI shows a blank page or 502 error

The RAG service or Ollama may still be initialising. Check:

```bash
docker compose ps
docker compose logs rag
```

Wait for all containers to show `healthy`. The first startup is slow.

### RAG image build fails

The RAG image is built from `scripts/rag/`. Common causes:
- No internet during build (needs to download Python packages)
- Docker out of disk space

Check with `docker compose logs rag` and `df -h`. To retry the build:

```bash
docker compose build rag
docker compose up -d
```

### Ollama model download is stuck

Ollama resumes interrupted downloads. Run:

```bash
docker compose exec ollama ollama pull qwen2.5:7b
```

If it keeps stalling, check your disk space: the model needs ~4.4 GB free.

### Kiwix shows "no ZIM files found"

Check that your ZIM files landed in the right directory:

```bash
ls /var/lib/allarkive/zim/
```

If the directory is empty, re-run `./scripts/fetch-bundle.sh balanced`.

### Port already in use

```bash
ss -tlnp | grep 8080    # or 8081, 3000, 11434, 8000
```

Stop whatever is using that port, or change AllArkive's port in `compose/.env`.

---

## What is next

Once the stack is running:
- Ask the AI a question and check that the numbered citations link back to
  the archive. If the answer says "no sources found," re-index and confirm
  the models are pulled.
- Try the full-text search mode to browse ZIM files directly via Kiwix.
- To share the archive with other devices on your network, see
  [`docs/deployment/lan-access.md`](../deployment/lan-access.md).

---

## What bootstrap.sh does

If you used `bootstrap.sh --bundle balanced`, it ran steps 1–8 automatically:
created directories, fetched and verified ZIMs, wrote resolved paths to
`compose/.env`, detected and avoided port conflicts, started the stack,
pulled both models, and ran the indexer. Paths chosen during bootstrap are
saved to `~/.config/allarkive/config.json` and reused on future runs.

The manual steps above are the exact equivalent, useful when you want more
control, need to debug a specific step, or are running on a machine where
Docker is not already set up.
