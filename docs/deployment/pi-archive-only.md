# Deployment: Raspberry Pi archive-only node (pattern C)

This guide runs `kiwix-serve` on a Raspberry Pi without Ollama or any AI
components. Use this pattern when:

- You want a dedicated, low-power archive node on the LAN.
- Another machine (laptop or Pi with the text-only stack) provides the AI layer.
- You are running a split deployment (see `docs/deployment/split.md`).

**Time estimate**: one to two hours, mostly downloading ZIM files.

---

## Hardware requirements

| Component | Minimum | Notes |
|-----------|---------|-------|
| Board | Raspberry Pi 4 (1 GB RAM) | kiwix-serve is very lean |
| Storage | USB SSD, 8 GB free | Size depends on bundle; see below |
| Power | Official 5 V / 3 A adapter | |
| Network | Ethernet recommended | Stable LAN connection for split use |

No Ollama means RAM requirements are minimal—even a 1 GB Pi 4 or a Pi Zero 2 W
can run `kiwix-serve` comfortably. A Pi 5 has no advantage here.

**Do not use SD card storage for ZIM files.** Even reads of large ZIM files
cause significant SD wear. A USB SSD is required.

### Bundle size guide

| Bundle | Approx. ZIM size | Recommended SSD |
|--------|-----------------|-----------------|
| `minimal` | ~3.5 GB | 16 GB |
| `balanced` | ~30 GB | 64 GB |
| `comprehensive` | ~130 GB+ | 256 GB+ |

---

## Step 1: Image the OS

Download **Raspberry Pi OS Lite (64-bit)** — the "Lite" variant, no desktop.
Bookworm (Debian 12) or later.

Flash with Raspberry Pi Imager. Before writing, configure:
- Hostname: `allarkive-archive` (or similar)
- SSH enabled
- Username and password
- Wi-Fi if needed (Ethernet preferred for a server)

Boot, confirm SSH:

```bash
ssh pi@allarkive-archive.local
```

Update:

```bash
sudo apt update && sudo apt full-upgrade -y
sudo reboot
```

---

## Step 2: Mount the USB SSD

```bash
lsblk
```

Format if needed (new SSD):

```bash
sudo fdisk /dev/sda     # new GPT partition table, one partition
sudo mkfs.ext4 /dev/sda1
```

Mount:

```bash
sudo mkdir -p /mnt/ssd
sudo mount /dev/sda1 /mnt/ssd
```

Persist across reboots—add to `/etc/fstab` (get UUID via `sudo blkid /dev/sda1`):

```
UUID=YOUR-UUID  /mnt/ssd  ext4  defaults,noatime  0  2
```

```bash
sudo mount -a
df -h /mnt/ssd
```

---

## Step 3: Install Docker

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker "$USER"
newgrp docker
docker compose version
```

---

## Step 4: Clone the repository

```bash
sudo mkdir -p /mnt/ssd/allarkive-repo
sudo chown "$USER" /mnt/ssd/allarkive-repo
git clone https://github.com/allarkive/allarkive /mnt/ssd/allarkive-repo
cd /mnt/ssd/allarkive-repo
```

---

## Step 5: Create data directory

```bash
mkdir -p /mnt/ssd/allarkive/zim
```

---

## Step 6: Download a bundle

Run `fetch-bundle.sh` from the Pi (it resumes partial downloads):

```bash
ALLARKIVE_DATA_DIR=/mnt/ssd/allarkive \
  scripts/fetch-bundle.sh minimal --dest /mnt/ssd/allarkive/zim
```

Replace `minimal` with `balanced` or `comprehensive` if you have the storage.

Verify:

```bash
ls -lh /mnt/ssd/allarkive/zim/*.zim
```

---

## Step 7: Configure kiwix

Copy the environment template:

```bash
cp compose/.env.example compose/.env
```

Edit `compose/.env`—only a few fields are relevant for archive-only:

```
ALLARKIVE_DATA_DIR=/mnt/ssd/allarkive

# Port binding for kiwix-serve.
# Default (127.0.0.1) means LAN access is not possible.
# For split deployment, change KIWIX_BIND to 0.0.0.0 and
# secure with a firewall. See docs/deployment/split.md.
KIWIX_BIND=127.0.0.1
KIWIX_PORT=8081
```

`WEBUI_SECRET_KEY` is not used by the archive-only stack; leave it blank.

---

## Step 8: Start kiwix-serve

```bash
cd /mnt/ssd/allarkive-repo
docker compose -f compose/docker-compose.pi-archive.yml --env-file compose/.env up -d
```

---

## Step 9: Smoke test

```bash
curl -sf http://127.0.0.1:8081/ > /dev/null && echo "kiwix OK"
```

Open a browser on the Pi (or over SSH port-forward):

```bash
ssh -L 8081:127.0.0.1:8081 pi@allarkive-archive.local
```

Then open `http://127.0.0.1:8081`. You should see the kiwix-serve article browser
with the downloaded archive listed.

---

## Enabling LAN access (required for split deployment)

By default, kiwix is bound to `127.0.0.1` and is not reachable from other
machines. For a split deployment, the archive node must be reachable from the
AI node.

Edit `compose/.env`:

```
KIWIX_BIND=0.0.0.0
```

Restart:

```bash
docker compose -f compose/docker-compose.pi-archive.yml --env-file compose/.env up -d
```

Verify kiwix is now listening on all interfaces:

```bash
ss -tlnp | grep 8081
```

Expected: `0.0.0.0:8081` instead of `127.0.0.1:8081`.

**Firewall recommendation**: if the Pi is on a home LAN, restrict access to
known IPs using `ufw`:

```bash
sudo apt install -y ufw
sudo ufw default deny incoming
sudo ufw allow ssh
# Allow kiwix from the AI node's IP only
sudo ufw allow from <AI-NODE-IP> to any port 8081
sudo ufw enable
```

For a full reverse-proxy setup with auth, see `docs/deployment/lan-access.md`.

---

## Port summary

| Service | Port | Bound to (default) |
|---------|------|--------------------|
| kiwix-serve | 8081 | 127.0.0.1 |

---

## Troubleshooting

### kiwix exits immediately

Check logs:

```bash
docker compose -f compose/docker-compose.pi-archive.yml logs kiwix
```

Common causes:
- No ZIM files in `/mnt/ssd/allarkive/zim/` — fetch a bundle first.
- The `ALLARKIVE_DATA_DIR` in `.env` does not match the actual mount path.

### Download stalls mid-bundle

`fetch-bundle.sh` uses `wget --continue`. Re-run it; it resumes. If the
connection is consistently dropping, try:

```bash
scripts/fetch-bundle.sh minimal --dest /mnt/ssd/allarkive/zim
```

### SSD not mounting after reboot

Check `/etc/fstab` entries and that the UUID matches:

```bash
sudo blkid /dev/sda1
grep ssd /etc/fstab
```

If the UUID has changed (replaced SSD), update `/etc/fstab`.

### ZIM file corrupted

Re-run `fetch-bundle.sh`. It verifies checksums and will re-download any file
that fails verification.

---

## Updating ZIM files

Kiwix releases updated ZIM snapshots periodically. To update:

1. Update the bundle manifest in `bundles/<name>/manifest.json` with new URLs
   and checksums.
2. Run `fetch-bundle.sh` — it replaces old files and verifies the new ones.
3. Restart kiwix-serve:

```bash
docker compose -f compose/docker-compose.pi-archive.yml restart kiwix
```

---

## What is next

- To add the AI layer to this Pi, see `docs/deployment/pi-text-only.md`.
- To connect an AI node to this archive node over the LAN, see
  `docs/deployment/split.md`.
