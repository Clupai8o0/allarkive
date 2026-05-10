# Installing AllArkive on a Linux server (headless)

This guide installs AllArkive on a headless Linux server over SSH, using
the docker-compose stack. It assumes Ubuntu 22.04 LTS or 24.04 LTS with
no desktop environment.

**Time estimate**: 15–30 minutes setup, then waiting for downloads.

---

## Quick start (automated)

Once Docker is installed (see Prerequisites), the rest is one command:

```bash
git clone https://github.com/Clupai8o0/allarkive.git
cd allarkive
cp compose/.env.example compose/.env
openssl rand -hex 32  # copy into WEBUI_SECRET_KEY= in compose/.env
nano compose/.env
./scripts/bootstrap.sh --bundle balanced
```

The manual steps below cover the same actions in detail.

---

## Prerequisites

### Hardware

| | Minimum | Recommended |
|-|---------|-------------|
| RAM | 8 GB | 16 GB |
| Free disk | 10 GB (minimal bundle + model) | 35 GB (balanced bundle + model) |
| CPU | Any x86_64 | More cores = faster inference |
| GPU | Not required | CUDA GPU detected automatically |

### Software

- **Docker Engine 24+** with the Compose plugin. On Ubuntu:

  ```bash
  sudo apt update
  sudo apt install -y ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
    | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
    | sudo tee /etc/apt/sources.list.d/docker.list
  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  sudo usermod -aG docker "$USER"
  ```

  Log out and back in so the group change takes effect. Verify:

  ```bash
  docker compose version
  ```

- `git`, `curl`, `openssl`:

  ```bash
  sudo apt install -y git curl openssl
  ```

---

## Viewing the UI without a local browser

AllArkive's landing page and Open WebUI are both web interfaces that bind to
`127.0.0.1` on the server. To access them from your local machine:

```bash
ssh -L 8080:127.0.0.1:8080 \
    -L 3000:127.0.0.1:3000 \
    -L 8081:127.0.0.1:8081 \
    user@your-server
```

While this SSH session is open, visit `http://localhost:8080` on your local
machine to reach the AllArkive landing page on the server.

For persistent access without SSH tunnels, see `docs/deployment/lan-access.md`.

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

Open `compose/.env` and paste the result into `WEBUI_SECRET_KEY=`.

On a server, also set `ALLARKIVE_DATA_DIR` to wherever your large storage lives.
Common choices:

```bash
# A mounted data volume:
ALLARKIVE_DATA_DIR=/mnt/data/allarkive

# External drive:
ALLARKIVE_DATA_DIR=/mnt/external/allarkive
```

---

## Step 3: Create data directories

```bash
sudo mkdir -p "${ALLARKIVE_DATA_DIR:-/var/lib/allarkive}"/{zim,index,models,data}
sudo chown -R "$USER" "${ALLARKIVE_DATA_DIR:-/var/lib/allarkive}"
```

---

## Step 4: Fetch a bundle

Choose a bundle based on available disk space:

| Bundle | Contents | Disk (ZIMs only) |
|--------|----------|-----------------|
| `minimal` | WikiMed + iFixit | ~4 GB |
| `balanced` | Wikipedia (text) + WikiMed + iFixit + SuperUser | ~28 GB |
| `comprehensive` | Full Wikipedia (images) + Gutenberg + Stack Exchange | ~330 GB |

```bash
./scripts/fetch-bundle.sh balanced
```

Checksum verification runs automatically. A failed checksum stops the script.

---

## Step 5: Start the stack

```bash
cd compose/
docker compose up -d
```

On first run, Docker does two things before services start:

1. **Builds the RAG image from source** (`scripts/rag/`) — 2–4 minutes.
2. **Pulls the remaining images** (kiwix-serve, Ollama, Open WebUI, nginx).

Subsequent starts skip both and are fast. On first run, Ollama also downloads
the default model (~4 GB) in the background.

Watch startup logs in a separate window:

```bash
docker compose logs -f
```

Wait for all containers to show `healthy` before proceeding.

### Checking service health

```bash
docker compose ps
```

All services should show `healthy` after a few minutes. If one stays
`unhealthy`, check its logs:

```bash
docker compose logs rag
docker compose logs ollama
```

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

Indexing time: roughly 10–30 minutes for the balanced bundle on a typical
server CPU. The index persists across restarts.

---

## Step 7: Verify

With an SSH tunnel open (see above), visit `http://localhost:8080`. Confirm:

1. Status line shows archive size and model name.
2. Searching an archive returns results.
3. Asking the AI returns an answer with numbered citations.

---

## Running as a system service

To start AllArkive automatically on reboot, create a systemd unit:

```bash
sudo tee /etc/systemd/system/allarkive.service <<EOF
[Unit]
Description=AllArkive docker-compose stack
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/home/${USER}/allarkive/compose
ExecStart=/usr/bin/docker compose up -d
ExecStop=/usr/bin/docker compose down
User=${USER}

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable allarkive
sudo systemctl start allarkive
```

Adjust `WorkingDirectory` to wherever you cloned the repository.

---

## Cleanup and uninstall

Use `scripts/cleanup.sh`. Nothing is deleted unless you explicitly ask.

| Command | What it removes |
|---------|----------------|
| `./scripts/cleanup.sh` | Stops and removes containers only. Data and images kept. |
| `./scripts/cleanup.sh --images` | Also removes Docker images (re-pulled on next start). |
| `./scripts/cleanup.sh --data` | Also deletes the data directory: ZIMs, models, RAG index, Open WebUI DB. **Irreversible.** Prompts before deleting. |
| `./scripts/cleanup.sh --all` | `--images` + `--data`. Full wipe. Prompts before deleting. |

After a full wipe, start fresh with `./scripts/bootstrap.sh --bundle balanced`.

---

## Port summary

All ports bind to `127.0.0.1` on the server by default.

| Service | Port | Bound to |
|---------|------|----------|
| Landing page | 8080 | 127.0.0.1 |
| kiwix-serve | 8081 | 127.0.0.1 |
| Open WebUI | 3000 | 127.0.0.1 |
| Ollama | 11434 | 127.0.0.1 |
| RAG service | 8000 | 127.0.0.1 |

For LAN or internet access, see `docs/deployment/lan-access.md`.

---

## Troubleshooting

### RAG image build fails

The RAG image builds from `scripts/rag/` on first `docker compose up`. If
it fails mid-build (network timeout, disk full):

```bash
docker compose build rag
docker compose up -d
```

Check disk with `df -h` — the build needs ~500 MB temporary space.

### Docker permission denied

Make sure your user is in the `docker` group and you have re-logged in:

```bash
groups | grep docker
```

If missing: `sudo usermod -aG docker "$USER"`, then log out and back in.

### Out of memory during inference

The default model (`qwen2.5:7b`) needs ~6 GB RAM. On a machine with 8 GB,
close other processes. Or use a smaller model: set `CHAT_MODEL=qwen2.5:3b`
and `OLLAMA_DEFAULT_MODEL=qwen2.5:3b` in `compose/.env`.

### Services keep restarting

Check logs:

```bash
docker compose logs --tail 50 <service-name>
```

Common causes: disk full (`df -h`), port conflict (`ss -tlnp | grep 8080`),
or missing `WEBUI_SECRET_KEY`.

### SSH tunnel drops

Use `autossh` or configure `ServerAliveInterval` in `~/.ssh/config`:

```
Host your-server
  ServerAliveInterval 60
  ServerAliveCountMax 3
```
