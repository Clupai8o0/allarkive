# Installing AllArkive on macOS

This guide installs AllArkive on macOS using Docker Desktop and the
docker-compose stack. Tested on macOS 13 (Ventura) and 14 (Sonoma) on
both Intel and Apple Silicon.

**Time estimate**: 15–30 minutes setup, then waiting for downloads.

---

## Quick start (automated)

```bash
git clone https://github.com/Clupai8o0/allarkive.git
cd allarkive
cp compose/.env.example compose/.env
openssl rand -hex 32  # copy into WEBUI_SECRET_KEY= in compose/.env
nano compose/.env
./scripts/bootstrap.sh --bundle balanced
```

On macOS, `bootstrap.sh` automatically uses `~/allarkive-data` as the data
directory (avoids the `/var/lib/` permission issue). No extra config needed.

The manual steps below are equivalent — follow them for more control.

---

## Prerequisites

### Hardware

| | Minimum | Recommended |
|-|---------|-------------|
| RAM | 8 GB | 16 GB |
| Free disk | 10 GB (minimal bundle + model) | 30 GB (balanced bundle + model) |

Apple Silicon (M1/M2/M3/M4) is supported. Ollama runs models natively on
Apple Silicon via Metal — no NVIDIA GPU needed.

### Software

- **Docker Desktop for Mac** (version 4.20 or later). Download from
  `https://www.docker.com/products/docker-desktop/`.

  After installing, open Docker Desktop and confirm it is running (the whale
  icon appears in the menu bar). Verify in a terminal:

  ```bash
  docker compose version
  ```

- **Homebrew** (optional but useful for `git`, `openssl`):

  ```bash
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  ```

  Or use the Xcode command-line tools:

  ```bash
  xcode-select --install
  ```

---

## Step 1: Clone the repository

```bash
git clone https://github.com/Clupai8o0/allarkive.git
cd allarkive
```

---

## Step 2: Set up configuration

```bash
cp compose/.env.example compose/.env
```

Generate a secret key:

```bash
openssl rand -hex 32
```

Open `compose/.env` in your editor and paste the result into
`WEBUI_SECRET_KEY=`.

### Data directory on macOS

The default data directory is `/var/lib/allarkive`. On macOS you will need to
either create this path or use a directory under your home folder.

**Option A — Use your home directory (simplest):**

Set in `compose/.env`:

```bash
ALLARKIVE_DATA_DIR=/Users/YOUR_USERNAME/allarkive-data
```

Then create it:

```bash
mkdir -p ~/allarkive-data/{zim,index,models,data}
```

**Option B — Use `/var/lib/allarkive` (matches Linux docs):**

```bash
sudo mkdir -p /var/lib/allarkive/{zim,index,models,data}
sudo chown -R "$USER" /var/lib/allarkive
```

---

## Step 3: Docker Desktop resource limits

By default, Docker Desktop allocates 50% of CPU and 50% of RAM. For the
`balanced` bundle with `qwen2.5:7b`, allocate at least 8 GB RAM to Docker.

Open **Docker Desktop → Settings → Resources** and set:
- Memory: 10 GB (or more if you have it)
- CPUs: at least 4

Click **Apply & Restart**.

---

## Step 4: Fetch a bundle

```bash
./scripts/fetch-bundle.sh balanced
```

The script downloads ZIM files to `$ALLARKIVE_DATA_DIR/zim/` and verifies
checksums. A failed checksum stops the script — do not proceed if this happens.

| Bundle | Contents | Disk (ZIMs only) |
|--------|----------|-----------------|
| `minimal` | WikiMed + iFixit | ~4 GB |
| `balanced` | Wikipedia (mini) + WikiMed + iFixit + SuperUser + Unix SE + Ask Ubuntu | ~23 GB |
| `comprehensive` | Full Wikipedia (images) + Gutenberg + Stack Exchange | ~330 GB |

---

## Step 5: Start the stack

```bash
cd compose/
docker compose up -d
```

On first run, Docker does two things before services start:

1. **Builds the RAG image from source** (`scripts/rag/`) — 2–4 minutes.
2. **Pulls the remaining images** (kiwix-serve, Ollama, Open WebUI, nginx).

Subsequent starts skip both steps and are fast.

Watch progress:

```bash
docker compose logs -f
```

Wait for all containers to report healthy:

```bash
docker compose ps
```

On first run also expect Ollama to download the default model (~4 GB) in
the background. Total first-run time: 5–15 minutes depending on network.

---

## Step 6: Index the archive

```bash
docker compose exec rag python indexer.py
```

The container already has `ZIM_DIR`, `INDEX_DIR`, and `OLLAMA_URL` set via
the compose file — no extra arguments needed. To force a full rebuild:

```bash
docker compose exec rag python indexer.py --force
```

Indexing time is roughly 10–30 minutes for the balanced bundle. The index
persists in `$ALLARKIVE_DATA_DIR/index/` across restarts.

---

## Step 7: Open the landing page

Visit `http://localhost:8080` in your browser.

Confirm the status line shows your archive size and model name. Test a search
and an AI question to verify citations are working.

---

## Apple Silicon notes

Ollama detects Apple Silicon automatically and uses Metal for GPU acceleration.
Model inference is significantly faster than on CPU. No extra configuration needed.

The Docker images are built for `linux/amd64` by default. Docker Desktop on
Apple Silicon runs them under Rosetta emulation with minimal performance penalty
for the services that do not run models (Kiwix, Open WebUI, landing page).
Ollama runs natively.

---

## Cleanup and uninstall

Use `scripts/cleanup.sh`. Nothing is deleted unless you explicitly ask.

| Command | What it removes |
|---------|----------------|
| `./scripts/cleanup.sh` | Stops and removes containers only. Data and images kept. |
| `./scripts/cleanup.sh --images` | Also removes Docker images (re-pulled on next start). |
| `./scripts/cleanup.sh --data` | Also deletes `~/allarkive-data`: ZIMs, models, RAG index, Open WebUI DB. **Irreversible.** Prompts before deleting. |
| `./scripts/cleanup.sh --all` | `--images` + `--data`. Full wipe. Prompts before deleting. |

After a full wipe, start fresh with `./scripts/bootstrap.sh --bundle balanced`.

---

## Port summary

| Service | Port | Bound to |
|---------|------|----------|
| Landing page | 8080 | 127.0.0.1 |
| kiwix-serve | 8081 | 127.0.0.1 |
| Open WebUI | 3000 | 127.0.0.1 |
| Ollama | 11434 | 127.0.0.1 |
| RAG service | 8000 | 127.0.0.1 |

---

## Troubleshooting

### Docker Desktop is not running

Click the whale icon in the menu bar and wait for it to show "Running". Then
retry `docker compose up -d`.

### RAG image build fails

The RAG image is built from `scripts/rag/` on first run. If it fails:
- Check you have internet access during build (downloads Python packages)
- Check Docker Desktop has enough disk (Settings → Resources → Disk image size)

To retry: `docker compose build rag && docker compose up -d`

### `bind: address already in use` on port 8080

Port 8080 is commonly used by dev servers. Change `LANDING_PORT=8082` (or any
free port) in `compose/.env` and restart.

### Model inference is very slow

Check Docker Desktop memory allocation (see Step 3). Also check that Docker
Desktop is not competing with other memory-heavy apps. On Apple Silicon, make
sure Rosetta is not running the Ollama container (it should not be, but you
can verify with `docker inspect allarkive-ollama-1 | grep -i platform`).

### Kiwix volumes not mounting

On macOS, Docker Desktop must have permission to access the directory you
set as `ALLARKIVE_DATA_DIR`. Go to **Docker Desktop → Settings → Resources →
File sharing** and add the parent directory of your data path.

### `WEBUI_SECRET_KEY` error

Open `compose/.env` and confirm `WEBUI_SECRET_KEY=` is set to a 64-character
hex string. If missing, generate one: `openssl rand -hex 32`.
