# Installing AllArkive on Windows (WSL2)

This guide installs AllArkive on Windows using WSL2 (Windows Subsystem for
Linux 2) and Docker Desktop. AllArkive runs inside a Linux environment on
your Windows machine — the Windows-native experience is limited to opening
a browser to view the UI.

**Tested on**: Windows 11 22H2 and later. Windows 10 21H2 and later should
also work with WSL2 support.

**Time estimate**: 30–60 minutes setup (WSL2 install included), then waiting
for downloads. After the stack starts, RAG indexing runs in the background —
**expect several hours for the balanced bundle on CPU**, faster with an
NVIDIA GPU passed into WSL2. See *Indexing takes hours* below.

---

## Quick start (automated)

Once WSL2 and Docker Desktop are installed (Steps 1–3 below), the rest is
one command inside your Ubuntu terminal:

```bash
git clone https://github.com/Clupai8o0/allarkive.git
cd allarkive
cp compose/.env.example compose/.env
openssl rand -hex 32  # copy into WEBUI_SECRET_KEY= in compose/.env
nano compose/.env
./scripts/bootstrap.sh --bundle balanced
```

The manual steps below cover WSL2 setup and the same actions in detail.

### Indexing takes hours — leave it running

When `bootstrap.sh` finishes, the **RAG indexer keeps running** in the
`rag` container, embedding every ZIM chunk through Ollama:

- **minimal bundle**: 15–30 minutes
- **balanced bundle**: several hours on CPU, faster with a CUDA GPU
- **comprehensive bundle**: overnight

The indexer is **resumable and idempotent** — you can close the WSL
terminal, suspend the machine, or reboot, and re-running `bootstrap.sh`
(or `docker compose exec rag python indexer.py`) picks up where it
left off.

Kiwix browsing at `http://localhost:8081` works **immediately**. RAG answers
in Open WebUI improve as coverage grows — "no sources found" early on is
expected for topics not yet indexed. Watch progress:

```bash
docker compose -f compose/docker-compose.yml logs -f rag
```

---

## Prerequisites

### Hardware

| | Minimum | Recommended |
|-|---------|-------------|
| RAM | 8 GB | 16 GB |
| Free disk | 20 GB (WSL2 + minimal bundle + model) | 80 GB (balanced bundle + model) |
| CPU | Any x86_64 | More cores = faster inference |
| GPU | Not required | NVIDIA GPU supported — see below |

### Windows version

WSL2 requires Windows 10 version 21H2 or later, or any version of Windows 11.
Check: **Start → Settings → System → About → Windows specifications**.

---

## Step 1: Install WSL2

Open PowerShell as Administrator and run:

```powershell
wsl --install
```

This installs WSL2 and Ubuntu (the default distro). Reboot when prompted.

After rebooting, Ubuntu will finish installing and ask you to create a
username and password. Use a simple username with no spaces.

Verify:

```powershell
wsl --status
# Should show: Default Version: 2
```

---

## Step 2: Install Docker Desktop for Windows

Download from `https://www.docker.com/products/docker-desktop/`.

During installation:
- Select **Use WSL 2 instead of Hyper-V** (should be pre-selected).
- After installation, open Docker Desktop.

Enable the WSL2 integration for your Ubuntu distro:
**Docker Desktop → Settings → Resources → WSL Integration → Enable integration
with additional distros → Ubuntu → Apply & Restart**.

Verify inside your Ubuntu terminal:

```bash
docker compose version
```

---

## Step 3: Configure WSL2 memory

By default WSL2 may claim too much RAM. Create `%USERPROFILE%\.wslconfig`
in Windows (not inside WSL) with:

```ini
[wsl2]
memory=10GB
processors=4
```

Adjust `memory` based on your system RAM (leave at least 2 GB for Windows).
Restart WSL for changes to take effect:

```powershell
wsl --shutdown
```

Then reopen your Ubuntu terminal.

---

## Step 4: Store data on the WSL2 filesystem

**Performance note**: Docker on Windows has fast I/O within the WSL2
filesystem (`~/` or `/var/lib/`) but very slow I/O when accessing Windows
paths like `/mnt/c/`. Keep all AllArkive data inside WSL2.

If you need a large external drive for ZIM files, format it as NTFS and
mount it inside WSL2:

```bash
# Example: a drive at D:\ mounted into WSL2
sudo mkdir /mnt/d
sudo mount -t drvfs D: /mnt/d
# Then set ALLARKIVE_DATA_DIR=/mnt/d/allarkive in compose/.env
```

---

## Step 5: Clone the repository (inside Ubuntu)

Open your Ubuntu terminal (search "Ubuntu" in Start):

```bash
git clone https://github.com/Clupai8o0/allarkive.git
cd allarkive
```

---

## Step 6: Set up configuration

```bash
cp compose/.env.example compose/.env
```

Generate a secret key:

```bash
openssl rand -hex 32
```

Open `compose/.env` (e.g. `nano compose/.env`) and paste the result into
`WEBUI_SECRET_KEY=`.

Create data directories:

```bash
sudo mkdir -p /var/lib/allarkive/{zim,index,models,data}
sudo chown -R "$USER" /var/lib/allarkive
```

---

## Step 7: Fetch a bundle

```bash
./scripts/fetch-bundle.sh balanced
```

| Bundle | Contents | Disk (ZIMs only) |
|--------|----------|-----------------|
| `minimal` | WikiMed + iFixit | ~4 GB |
| `balanced` | Wikipedia (mini) + WikiMed + iFixit + SuperUser + Unix SE + Ask Ubuntu | ~23 GB |
| `comprehensive` | Full Wikipedia (images) + Gutenberg + Stack Exchange | ~330 GB |

---

## Step 8: Start the stack

```bash
cd compose/
docker compose up -d
```

On first run, Docker does two things before services start:

1. **Builds the RAG image from source** (`scripts/rag/`) — 2–4 minutes.
2. **Pulls the remaining images** (kiwix-serve, Ollama, Open WebUI, nginx).

If the build fails with a network error, check Docker Desktop is running and
WSL integration is enabled (Step 2).

Watch logs during first startup:

```bash
docker compose logs -f
```

Wait for all containers to show `healthy`:

```bash
docker compose ps
```

---

## Step 9: Pull AI models

Two models are needed — the chat model and the embedding model. Pull them
before indexing:

```bash
# Chat model (~4 GB for qwen2.5:7b):
docker compose exec ollama ollama pull qwen2.5:7b

# Embedding model (~270 MB):
docker compose exec ollama ollama pull nomic-embed-text
```

Both pulls resume automatically if interrupted.

---

## Step 10: Index the archive

```bash
docker compose exec rag python indexer.py \
    --zim-dir /data \
    --index-dir /index \
    --ollama-url http://ollama:11434
```

To force a full rebuild:

```bash
docker compose exec rag python indexer.py \
    --zim-dir /data \
    --index-dir /index \
    --ollama-url http://ollama:11434 \
    --force
```

---

## Step 11: Open the landing page

In your Windows browser (not inside WSL), visit `http://localhost:8080`.

WSL2 automatically forwards ports from the Linux environment to Windows
localhost, so you do not need to do anything extra.

---

## What bootstrap.sh does

`bootstrap.sh` covers steps 5–11 automatically once WSL2 and Docker Desktop
are set up: creates directories, fetches and verifies ZIMs, writes storage
paths to `compose/.env`, detects port conflicts, starts the stack, pulls both
models, and runs the indexer. The manual steps above are the exact equivalent.

---

## NVIDIA GPU acceleration

If your machine has an NVIDIA GPU with the Windows NVIDIA driver (version 470+):

1. Install the [CUDA on WSL2](https://docs.nvidia.com/cuda/wsl-user-guide/index.html)
   drivers from NVIDIA (Windows-side only — do not install CUDA inside WSL).
2. Inside WSL, verify:
   ```bash
   nvidia-smi
   ```
3. Start AllArkive with the GPU profile:
   ```bash
   docker compose --profile gpu up -d
   ```

---

## Port summary

| Service | Port | Access from Windows browser |
|---------|------|----------------------------|
| Landing page | 8080 | http://localhost:8080 |
| kiwix-serve | 8081 | http://localhost:8081 |
| Open WebUI | 3000 | http://localhost:3000 |
| Ollama | 11434 | http://localhost:11434 |
| RAG service | 8000 | http://localhost:8000 |

---

## Stopping and starting

```bash
# In your Ubuntu terminal:
cd allarkive/compose
docker compose down

# Start again:
docker compose up -d
```

Docker Desktop must be running before starting the stack.

---

## Cleanup and uninstall

Run these inside your Ubuntu (WSL2) terminal. Nothing is deleted unless you
explicitly ask.

| Command | What it removes |
|---------|----------------|
| `./scripts/cleanup.sh` | Stops and removes containers only. Data and images kept. |
| `./scripts/cleanup.sh --images` | Also removes Docker images (re-pulled on next start). |
| `./scripts/cleanup.sh --data` | Also deletes the data directory: ZIMs, models, RAG index, Open WebUI DB. **Irreversible.** Prompts before deleting. |
| `./scripts/cleanup.sh --all` | `--images` + `--data`. Full wipe. Prompts before deleting. |

After a full wipe, start fresh with `./scripts/bootstrap.sh --bundle balanced`.

---

## Troubleshooting

### RAG image build fails

Check that Docker Desktop is running and WSL integration is enabled (Step 2).
If the build fails partway, retry with:

```bash
docker compose build rag && docker compose up -d
```

### WSL2 does not start

Open PowerShell as Administrator and run:

```powershell
wsl --update
wsl --shutdown
```

Then reopen Ubuntu.

### Docker commands not found inside WSL2

Ensure Docker Desktop is running and WSL integration is enabled for your
Ubuntu distro (see Step 2). Restart Docker Desktop if it was already
enabled.

### Ports not forwarding to Windows

WSL2 forwards ports automatically in recent builds of Windows 11. If
`localhost:8080` does not work, try the WSL2 IP address directly:

```bash
# Inside WSL2:
ip addr show eth0 | grep 'inet '
# Note the IP, e.g. 172.18.45.2
```

Then visit `http://172.18.45.2:8080` in your Windows browser.

### Slow downloads inside WSL2

DNS resolution inside WSL2 can be slow on some Windows setups. Add to
`/etc/wsl.conf` inside Ubuntu (create if missing):

```ini
[network]
generateResolvConf = false
```

Then edit `/etc/resolv.conf` to use `nameserver 8.8.8.8`. Restart WSL:
`wsl --shutdown`.

### Antivirus interference

Windows Defender or third-party antivirus may scan every file written to the
WSL2 filesystem, dramatically slowing ZIM downloads and indexing. Add the
WSL2 virtual disk (`%LOCALAPPDATA%\Packages\CanonicalGroupLimited.Ubuntu*`)
to your antivirus exclusion list.

### Out of disk space

WSL2 allocates a virtual disk that grows as needed but does not shrink
automatically. If you delete large files inside WSL and need to reclaim
Windows disk space:

```powershell
# In PowerShell (WSL must be shut down first):
wsl --shutdown
diskpart
# then: select vdisk file="path\to\ext4.vhdx", compact vdisk
```
