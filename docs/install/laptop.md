# Installing AllArkive on a laptop (manual)

> **Status**: draft v0—written ahead of the first manual install on Laptop 1.
> Follow each step, note every error, every unexpected prompt, every command that
> behaved differently than described. Those gaps are what this milestone is for.
> Once Milestone 3 is complete, this guide will be updated to use
> `docker compose up` and the manual path will move to a reference appendix.

This guide installs AllArkive's three layers manually on a Linux laptop
(Ubuntu 22.04 LTS or 24.04 LTS). Doing it by hand first is how we learned
what needs to be automated. If you are on macOS, see `docs/install/macos.md`
(not yet written—file an issue if you hit macOS-specific snags while following
this guide).

**Time estimate**: two to four hours, mostly waiting for downloads.

---

## Prerequisites

### Hardware

- RAM: 8 GB minimum; 16 GB recommended (the 7B model loads into RAM)
- Free disk: 30 GB minimum for one small ZIM and one model;
  100 GB+ for the balanced bundle
- CPU: any x86\_64; more cores improve model inference speed
- GPU: optional—Ollama detects CUDA GPUs automatically;
  the install path is the same either way

### Software

- Ubuntu 22.04 LTS or 24.04 LTS, fully updated
- Python 3.11 or later: `python3 --version`
- `curl`, `wget`, `sha256sum` (present on most Ubuntu installs)

Install system dependencies if missing:

```bash
sudo apt update && sudo apt install -y \
  curl wget python3.11 python3.11-venv python3-pip openssl
```

### Storage directories

Create the shared data layout before installing any component.
Everything goes under `/var/lib/allarkive/` so there is one place to
back up and one place to look when things break.

```bash
sudo mkdir -p /var/lib/allarkive/{zim,index,models,data}
sudo chown -R "$USER" /var/lib/allarkive
```

Confirm the directories exist:

```bash
ls /var/lib/allarkive/
# Expected: data  index  models  zim
```

---

## Step 1: Install Ollama

Ollama manages open-weight models and exposes an HTTP API on port 11434.

### Installation

```bash
curl -fsSL https://ollama.com/install.sh | sh
```

After installing, record the version:

```bash
ollama --version
# Record here: ____________
```

### Redirect model storage

By default Ollama stores models in `~/.ollama/models`. Redirect to the
shared layout so they live with the rest of AllArkive's data:

```bash
# Add to ~/.profile or /etc/environment:
export OLLAMA_MODELS=/var/lib/allarkive/models
```

Apply the change immediately for the current session:

```bash
export OLLAMA_MODELS=/var/lib/allarkive/models
sudo systemctl restart ollama
```

### Bind to localhost only

Verify Ollama is listening only on the loopback interface:

```bash
ss -tlnp | grep 11434
```

Expected: a line containing `127.0.0.1:11434`.

If the output shows `0.0.0.0:11434`, Ollama is exposed on all interfaces.
Create a systemd override to fix this:

```bash
sudo mkdir -p /etc/systemd/system/ollama.service.d/
sudo tee /etc/systemd/system/ollama.service.d/override.conf <<'EOF'
[Service]
Environment="OLLAMA_HOST=127.0.0.1"
EOF
sudo systemctl daemon-reload && sudo systemctl restart ollama
```

Recheck `ss -tlnp | grep 11434`. Record what you see: `____________`.

### Pull the recommended model

> **Open question**: the default model is not yet decided—see `TODO.md`.
> Use `qwen2.5:7b` for this smoke test. Update this line once the open
> question in `TODO.md` is resolved.

```bash
ollama pull qwen2.5:7b
```

Expected download: approximately 4.4 GB. Record actual duration: `____________`.

### Smoke test Ollama

```bash
ollama run qwen2.5:7b "What is the capital of France? Reply in one sentence."
```

Expected: a short, correct response. Exit with `/bye`.

Record the output or any error: `____________`.

If Ollama responds correctly, the AI layer is working.

---

## Step 2: Install Kiwix

`kiwix-serve` reads ZIM files and exposes an HTTP server on port 8081.

### Installation

Download the static binary from the official release page. Find the current
release at `https://download.kiwix.org/release/kiwix-tools/` and pick the
`_linux-x86_64` build.

```bash
# Set the version—check the release page for the current value.
KIWIX_VERSION="3.7.0"
KIWIX_ARCHIVE="kiwix-tools_linux-x86_64-${KIWIX_VERSION}.tar.gz"

wget "https://download.kiwix.org/release/kiwix-tools/${KIWIX_ARCHIVE}" \
  -O /tmp/kiwix-tools.tar.gz

# Verify the SHA-256. Download the checksum file alongside the binary.
wget "https://download.kiwix.org/release/kiwix-tools/${KIWIX_ARCHIVE}.sha256" \
  -O /tmp/kiwix-tools.tar.gz.sha256
sha256sum -c /tmp/kiwix-tools.tar.gz.sha256
```

Expected: `OK`. Do not proceed if verification fails—re-download.

Extract and install:

```bash
tar -xzf /tmp/kiwix-tools.tar.gz -C /tmp/
sudo install -m 0755 \
  /tmp/kiwix-tools_linux-x86_64-${KIWIX_VERSION}/kiwix-serve \
  /usr/local/bin/kiwix-serve

kiwix-serve --version
# Record here: ____________
```

### Download a test ZIM

Use Simple English Wikipedia for the smoke test—it is small (~200 MB)
and lets us test ZIM serving without a multi-hour download.

Find the current release filename at:
`https://download.kiwix.org/zim/wikipedia/`

Look for `wikipedia_en_simple_all_maxi_YYYY-MM.zim`.

```bash
cd /var/lib/allarkive/zim

# Replace YYYY-MM with the current release date shown on the download page.
ZIM_FILE="wikipedia_en_simple_all_maxi_YYYY-MM.zim"

wget "https://download.kiwix.org/zim/wikipedia/${ZIM_FILE}"

# Download and verify the checksum.
wget "https://download.kiwix.org/zim/wikipedia/${ZIM_FILE}.sha256"
sha256sum -c "${ZIM_FILE}.sha256"
```

Expected: `OK`. Record actual filename used: `____________`.
Record SHA-256: `____________`.

### Run kiwix-serve

```bash
kiwix-serve \
  --port 8081 \
  --address 127.0.0.1 \
  /var/lib/allarkive/zim/${ZIM_FILE}
```

Leave this running in a terminal.

### Smoke test Kiwix

In a second terminal:

```bash
curl -s http://127.0.0.1:8081/ | head -5
```

Expected: HTML from kiwix-serve. Open `http://127.0.0.1:8081` in a browser
and verify articles load.

Record any errors: `____________`.

---

## Step 3: Install Open WebUI

Open WebUI is the chat interface. It connects to Ollama over HTTP and
provides a browser-based conversation UI. The RAG layer (Milestone 4)
will sit between Open WebUI and Ollama.

### Installation

Use a virtual environment to isolate Open WebUI's Python dependencies:

```bash
python3.11 -m venv /var/lib/allarkive/webui-venv
source /var/lib/allarkive/webui-venv/bin/activate
pip install open-webui

# Record the installed version:
pip show open-webui | grep '^Version'
# Record here: ____________
```

### Generate a secret key

Open WebUI uses a secret key to sign sessions. Generate one now and save it—
you will need it when Milestone 3 converts this to a compose file.

```bash
openssl rand -hex 32
# Record the value in a safe place outside this repo: ____________
```

### Start Open WebUI

```bash
source /var/lib/allarkive/webui-venv/bin/activate

DATA_DIR=/var/lib/allarkive/data \
WEBUI_SECRET_KEY="<paste the key you generated above>" \
open-webui serve --host 127.0.0.1 --port 3000
```

On first start, Open WebUI runs database migrations and then prints a URL.

### Smoke test Open WebUI

Open `http://127.0.0.1:3000` in a browser.

Expected: the Open WebUI setup wizard or login screen.

1. Create an admin account.
2. Go to **Settings → Connections**.
3. Set the Ollama API URL to `http://127.0.0.1:11434`.
4. Click **Verify**—it should detect `qwen2.5:7b`.

Record any errors: `____________`.

---

## Integration smoke test

With all three services running, confirm the AI layer talks to Open WebUI.

1. Open `http://127.0.0.1:3000`.
2. Start a new chat; select `qwen2.5:7b`.
3. Send: "What is 2 + 2?"
4. Confirm you receive an answer.

This tests Open WebUI → Ollama. Full RAG (answers citing the archive) is
not available until Milestone 4. The goal here is just to confirm the
layers communicate.

Record the result: `____________`.

---

## Running all services together

For now, open three terminals and start each service manually. Milestone 3
will replace this with a single `docker compose up`.

**Terminal 1 — Ollama** (usually already running as a systemd service):

```bash
# If not managed by systemd:
OLLAMA_MODELS=/var/lib/allarkive/models OLLAMA_HOST=127.0.0.1 ollama serve
```

**Terminal 2 — Kiwix**:

```bash
kiwix-serve \
  --port 8081 \
  --address 127.0.0.1 \
  /var/lib/allarkive/zim/*.zim
```

**Terminal 3 — Open WebUI**:

```bash
source /var/lib/allarkive/webui-venv/bin/activate
DATA_DIR=/var/lib/allarkive/data \
WEBUI_SECRET_KEY="<your key>" \
open-webui serve --host 127.0.0.1 --port 3000
```

---

## Port summary

| Service | Port | Bound to |
|---------|------|----------|
| Ollama | 11434 | 127.0.0.1 |
| kiwix-serve | 8081 | 127.0.0.1 |
| Open WebUI | 3000 | 127.0.0.1 |

Nothing is exposed outside the machine by default.

---

## Troubleshooting

### `ollama` command not found after install

Check `/usr/local/bin/ollama`. If present, ensure `/usr/local/bin` is on
your `$PATH`. Re-run the install script if missing.

### Ollama model download stalls

Run `ollama pull qwen2.5:7b` again—Ollama resumes from where it stopped.

### Port already in use

```bash
ss -tlnp | grep 8081   # or 11434 or 3000
```

Find the process ID in the output and stop it with `kill <PID>`, or change
the AllArkive port in the start command.

### Kiwix returns no content

Confirm the ZIM file path is correct and the file is not corrupt:

```bash
sha256sum /var/lib/allarkive/zim/*.zim
```

Compare against the `.sha256` file you saved during download.

### Open WebUI cannot reach Ollama

Verify Ollama is running and listening:

```bash
curl -s http://127.0.0.1:11434/api/version
```

Expected: JSON with an `"version"` field. If this fails, Ollama is not
running or is bound to a different address.

### Open WebUI login loop / session errors

A mismatched or missing `WEBUI_SECRET_KEY` causes session tokens to
invalidate on restart. Set a stable value and keep it consistent across
restarts.

---

## What to record during your install

When you do the install on Laptop 1, fill in every `____________` above.
Also note:

- Any step where the command shown did not work as written
- Any step that was confusing or that required outside research
- Any error message that does not appear in the troubleshooting section
- Approximate wall-clock time for each major step

Each gap is a future issue or a doc fix. File them.

---

## What is next

Once Laptop 1 is working and snags are documented:

1. Sham follows this guide on Laptop 2 from scratch, without asking Sam.
   Each confusion or error becomes an issue.
2. All issues from both installs are resolved and this guide is marked v1.
3. Milestone 3 converts these manual steps into `compose/docker-compose.yml`
   and `scripts/bootstrap.sh`.
4. Milestone 4 adds the RAG pipeline so AI responses cite sources from
   the archive.
