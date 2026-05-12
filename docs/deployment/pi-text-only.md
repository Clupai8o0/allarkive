# Deployment: Raspberry Pi text-only stack (pattern B)

This guide runs the full AllArkive stack—kiwix-serve, Ollama, the RAG service,
Open WebUI, and the landing page—on a Raspberry Pi 4 or Pi 5 using a USB SSD
for storage. The "text-only" label means the recommended bundle (`minimal`) uses
text-only ZIM archives; the AI and RAG layers are present and fully functional.

**Time estimate**: two to four hours, mostly downloading images and model weights.

---

## Hardware requirements

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| Board | Raspberry Pi 4 (4 GB RAM) | Pi 4 (8 GB) or Pi 5 (8 GB) |
| Storage | USB SSD, 32 GB free | USB SSD, 64 GB+ |
| Power | Official 5 V / 3 A adapter | Official 5 V / 5 A (Pi 5) |
| Network | Ethernet or Wi-Fi | Ethernet for downloads |

**Do not use an SD card for AllArkive data.** SD cards fail under the sustained
random-write load of model inference and vector indexing. Boot from SD, store
everything under `/mnt/ssd` on the USB SSD.

### RAM guidance by model

| Pi RAM | Recommended chat model | Notes |
|--------|------------------------|-------|
| 4 GB | `qwen2.5:1.5b` | Default. Leaves ~1.5 GB headroom. |
| 8 GB | `qwen2.5:3b` or `phi3.5:3.8b` | Better answers, still fits. |
| 8 GB (Pi 5) | `qwen2.5:7b` | Works with `OLLAMA_MEMORY_LIMIT=6G`. |

---

## Step 1: Image the OS

Download **Raspberry Pi OS Lite (64-bit)** from
`https://www.raspberrypi.com/software/operating-systems/` — choose the
"Lite" variant (no desktop). Bookworm (Debian 12) or later.

Flash it with Raspberry Pi Imager. Before writing, click the gear icon and:
- Set a hostname (`allarkive-pi` works)
- Enable SSH
- Set a username and password
- Configure Wi-Fi if you are not using Ethernet

Boot the Pi, confirm SSH access:

```bash
ssh pi@allarkive-pi.local
```

Update the system:

```bash
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

---

## Step 2: Mount the USB SSD

Identify the SSD device:

```bash
lsblk
```

Look for a disk (`sda`, `sdb`, etc.) without a partition listed in `MOUNTPOINTS`.
Your SSD is typically `/dev/sda` with a partition at `/dev/sda1`.

If the SSD is new and has no partition, format it:

```bash
sudo fdisk /dev/sda   # create a new GPT partition table and one partition
sudo mkfs.ext4 /dev/sda1
```

Mount it:

```bash
sudo mkdir -p /mnt/ssd
sudo mount /dev/sda1 /mnt/ssd
```

Make the mount survive reboots. Add to `/etc/fstab`:

```bash
# Get the UUID of the partition
sudo blkid /dev/sda1
```

Add a line to `/etc/fstab` (replace `YOUR-UUID` with the value from `blkid`):

```
UUID=YOUR-UUID  /mnt/ssd  ext4  defaults,noatime  0  2
```

Verify:

```bash
sudo mount -a
df -h /mnt/ssd
```

Expected: `/mnt/ssd` mounted with available space matching your SSD size.

---

## Step 3: Install Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"
newgrp docker
```

Verify:

```bash
docker version
docker compose version
```

Expected: Docker Engine 24+ and Compose 2.x.

---

## Step 4: Clone the repository

```bash
sudo mkdir -p /mnt/ssd/allarkive-repo
sudo chown "$USER" /mnt/ssd/allarkive-repo
git clone https://github.com/allarkive/allarkive /mnt/ssd/allarkive-repo
cd /mnt/ssd/allarkive-repo
```

---

## Step 5: Configure the environment

```bash
cp compose/.env.example compose/.env
```

Edit `compose/.env`:

```bash
nano compose/.env
```

Required changes:

```
# Generate a secret key:
#   openssl rand -hex 32
WEBUI_SECRET_KEY=<paste the output here>

# Point all data at the USB SSD
ALLARKIVE_DATA_DIR=/mnt/ssd/allarkive

# Set the smaller Pi model
OLLAMA_DEFAULT_MODEL=qwen2.5:1.5b
CHAT_MODEL=qwen2.5:1.5b

# Tune RAM limit to your board (4G for 4 GB Pi, 6G for 8 GB Pi)
OLLAMA_MEMORY_LIMIT=4G
```

---

## Step 6: Run bootstrap

```bash
scripts/bootstrap.sh --pi --bundle minimal
```

This will:
1. Check prerequisites (Docker, disk space)
2. Create data directories under `/mnt/ssd/allarkive`
3. Download the `minimal` bundle ZIMs (~3.5 GB) and verify checksums
4. Start the Compose stack (`compose/docker-compose.pi.yml`)
5. Pull `qwen2.5:1.5b` (~900 MB) and `nomic-embed-text` (~270 MB) into Ollama
6. Run the RAG indexer over the downloaded ZIMs

**Wall-clock time**: 30–90 minutes for download + image build on a
reasonable connection, depending on Pi generation. After that, the
**RAG indexer keeps running in the background** — on a Pi 4 expect
roughly **1–3 hours for the minimal bundle**, longer for balanced.
Leave it running: the indexer is resumable and idempotent, and Kiwix
browsing at `http://<pi-ip>:8081` works immediately. RAG answers in
Open WebUI improve as coverage grows — "no sources found" early on is
expected for topics not yet indexed. Watch progress:

```bash
docker compose -f compose/docker-compose.pi.yml logs -f rag
```

### If the indexer OOMs during first run

The Pi 4 with 4 GB RAM can struggle to run Ollama and the indexer at the same time.
If the indexer crashes, run it after Ollama is idle:

```bash
docker compose -f compose/docker-compose.pi.yml exec rag \
  python indexer.py --zim-dir /data --index-dir /index --ollama-url http://ollama:11434
```

---

## Step 7: Smoke test

From the Pi (or any machine on the same network with the right port forwarded):

```bash
# Check the landing page
curl -s http://127.0.0.1:8080/ | grep -o '<title>[^<]*</title>'

# Check kiwix is serving
curl -sf http://127.0.0.1:8081/ > /dev/null && echo "kiwix OK"

# Check Ollama
curl -s http://127.0.0.1:11434/api/version

# Check RAG health
curl -s http://127.0.0.1:8000/health
```

Open `http://127.0.0.1:8080` in a browser (or forward the port via SSH):

```bash
ssh -L 8080:127.0.0.1:8080 pi@allarkive-pi.local
```

Then open `http://127.0.0.1:8080` on your laptop.

---

## Port summary

| Service | Port | Bound to |
|---------|------|----------|
| Landing page | 8080 | 127.0.0.1 |
| kiwix-serve | 8081 | 127.0.0.1 |
| RAG service | 8000 | 127.0.0.1 |
| Open WebUI | 3000 | 127.0.0.1 |
| Ollama | 11434 | 127.0.0.1 |

Nothing is exposed to the LAN by default. See `docs/deployment/lan-access.md`
for the opt-in remote-access path.

---

## Troubleshooting

### Docker daemon not running after reboot

```bash
sudo systemctl enable docker
sudo systemctl start docker
```

### Ollama OOM-killed

Reduce `OLLAMA_MEMORY_LIMIT` in `compose/.env` and restart:

```bash
docker compose -f compose/docker-compose.pi.yml restart ollama
```

Or switch to a smaller model (`qwen2.5:1.5b` → `llama3.2:1b` at ~600 MB).

### ZIM download stalls

`fetch-bundle.sh` uses `wget --continue`. Re-run the script; it resumes from
where it left off:

```bash
scripts/fetch-bundle.sh minimal --dest /mnt/ssd/allarkive/zim
```

### Kiwix exits immediately ("no ZIM files found")

Confirm ZIM files exist and the path is correct:

```bash
ls -lh /mnt/ssd/allarkive/zim/*.zim
```

If empty, fetch the bundle before starting the stack.

### RAG indexer is slow

Pi 4 with 4 GB RAM processes roughly 5–15 articles per second during embedding.
For the minimal bundle (~400 MB of text), expect 15–30 minutes. Use
`RAG_MAX_ARTICLES` in `.env` to cap indexing time during testing:

```
RAG_MAX_ARTICLES=500
```

### Port already bound

```bash
ss -tlnp | grep 8080
```

Find the PID and stop the conflicting process, or change `LANDING_PORT` in
`compose/.env`.

### Check all service logs

```bash
docker compose -f compose/docker-compose.pi.yml logs -f
```

---

## Updating

To pull new images and restart:

```bash
cd /mnt/ssd/allarkive-repo
git pull
docker compose -f compose/docker-compose.pi.yml pull
docker compose -f compose/docker-compose.pi.yml up -d
```

Re-index after adding new ZIM files:

```bash
docker compose -f compose/docker-compose.pi.yml exec rag \
  python indexer.py --zim-dir /data --index-dir /index --ollama-url http://ollama:11434
```

---

## What is next

- To run a Pi as a dedicated archive node (no AI), see
  `docs/deployment/pi-archive-only.md`.
- To connect this Pi to a remote Kiwix archive node, see
  `docs/deployment/split.md`.
- To expose the stack to the LAN, see `docs/deployment/lan-access.md`.
