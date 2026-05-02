# Deployment: split topology (AI on laptop, archive on Pi)

In a split deployment, one machine runs the AI layer (Ollama + RAG) and a
separate machine runs the archive layer (kiwix-serve). The RAG service on the
AI node fetches articles from the archive node over the LAN, then passes
retrieved passages to Ollama.

```
┌─────────────────────────────┐         ┌──────────────────────────┐
│  Laptop (AI node)           │         │  Pi (archive node)       │
│                             │         │                          │
│  Ollama (port 11434)        │         │  kiwix-serve (port 8081) │
│  RAG service (port 8000)    │◄────────│                          │
│  Open WebUI (port 3000)     │  LAN    │  USB SSD: ZIM files      │
│  Landing page (port 8080)   │         │                          │
└─────────────────────────────┘         └──────────────────────────┘
```

Use this pattern when:
- Your laptop does not have enough storage for large ZIM bundles.
- You want a low-power, always-on archive node and a laptop that joins when needed.
- You are testing the Pi archive node (pattern C) alongside the full AI stack.

---

## Prerequisites

Before starting, complete the setup for each node:

| Node | Guide |
|------|-------|
| Archive node (Pi) | `docs/deployment/pi-archive-only.md` |
| AI node (laptop) | `docs/install/laptop.md` + `docs/deployment/` or standard docker-compose |

The archive node must have:
- kiwix-serve running and reachable on the LAN (i.e., bound to `0.0.0.0`, not
  just `127.0.0.1` — see the "Enabling LAN access" section in
  `docs/deployment/pi-archive-only.md`)
- ZIM files downloaded and confirmed working

The AI node must have:
- AllArkive cloned and configured
- `compose/.env` filled in

---

## Step 1: Find the archive node's IP address

On the Pi:

```bash
ip -4 addr show | grep inet
```

Look for the LAN IP (typically `192.168.x.x` or `10.x.x.x`). Note it.

Alternatively, use the hostname if mDNS is working:

```bash
ping -c 1 allarkive-archive.local
```

Use whichever address resolves reliably. For a home network, mDNS hostnames
are convenient but can be flaky—a static DHCP lease or fixed IP is more stable.

---

## Step 2: Confirm kiwix is reachable from the laptop

From the laptop:

```bash
curl -sf http://<ARCHIVE-NODE-IP>:8081/ > /dev/null && echo "kiwix reachable"
```

If this fails:
- Check that `KIWIX_BIND=0.0.0.0` in the Pi's `compose/.env`.
- Check that the Pi's firewall allows port 8081 from the laptop's IP.
- Check that both machines are on the same LAN segment.

---

## Step 3: Configure the AI node

On the laptop, edit `compose/.env`:

```
# Point the RAG service at the Pi's kiwix-serve instead of localhost
KIWIX_PUBLIC_URL=http://<ARCHIVE-NODE-IP>:8081
```

This variable controls two things:
1. The URL the RAG service uses to fetch article text for retrieval.
2. The base URL embedded in citation links returned to the user.

If the Pi has a stable hostname:

```
KIWIX_PUBLIC_URL=http://allarkive-archive.local:8081
```

---

## Step 4: Update the RAG service configuration

The RAG service reads ZIM files directly for indexing (mounting the local `/data`
volume) **and** talks to kiwix-serve for citation link generation. In a split
deployment, the AI node does not have ZIM files locally—the archive is on the Pi.

### Option A: Mount the Pi's SSD over the network (NFS)

Export the ZIM directory from the Pi and mount it on the laptop. This lets the
indexer read ZIM content directly.

On the Pi:

```bash
sudo apt install -y nfs-kernel-server
```

Add to `/etc/exports`:

```
/mnt/ssd/allarkive/zim  <LAPTOP-IP>(ro,sync,no_subtree_check)
```

```bash
sudo exportfs -ra
```

On the laptop:

```bash
sudo apt install -y nfs-common
sudo mkdir -p /mnt/archive-zim
sudo mount <ARCHIVE-NODE-IP>:/mnt/ssd/allarkive/zim /mnt/archive-zim
```

Make it persistent in `/etc/fstab`:

```
<ARCHIVE-NODE-IP>:/mnt/ssd/allarkive/zim  /mnt/archive-zim  nfs  ro,_netdev  0  0
```

Set `ZIM_DIR` in `compose/.env` to `/mnt/archive-zim`, and update the RAG
service volume in `compose/docker-compose.yml`:

```yaml
rag:
  volumes:
    - "/mnt/archive-zim:/data:ro"
    - "${ALLARKIVE_DATA_DIR:-/var/lib/allarkive}/index:/index"
```

### Option B: Pre-build the index on the Pi and copy it to the laptop

Index the ZIMs on the Pi (or any machine with local ZIM access), then copy
the resulting `index.db` to the laptop's index directory.

```bash
# On the Pi (or a machine with the ZIMs):
docker run --rm \
  -v /mnt/ssd/allarkive/zim:/data:ro \
  -v /tmp/index:/index \
  -e OLLAMA_URL=http://<OLLAMA-IP>:11434 \
  allarkive-rag:0.1.0 \
  python indexer.py --zim-dir /data --index-dir /index

# Copy the index to the laptop:
scp /tmp/index/index.db laptop:/var/lib/allarkive/index/index.db
```

This avoids the NFS dependency. The index only needs to be rebuilt when ZIM
content changes.

---

## Step 5: Start the AI node

```bash
docker compose -f compose/docker-compose.yml --env-file compose/.env up -d
```

The RAG service will now generate citation links pointing at the Pi's kiwix-serve.

---

## Step 6: Smoke test the split stack

From the laptop, test that a RAG query returns citations with the archive node's IP:

```bash
curl -s http://127.0.0.1:8000/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model": "allarkive-rag", "messages": [{"role": "user", "content": "What is Wikipedia?"}]}' \
  | python3 -m json.tool | grep kiwix
```

Expected: citation URLs containing the Pi's IP or hostname.

Open `http://127.0.0.1:8080` (landing page) in a browser, run a chat query,
and click a citation. It should load an article from the Pi's kiwix-serve.

---

## Network topology notes

### Static IP or DHCP reservation

For reliable operation, give the archive Pi a static IP (via your router's DHCP
reservation feature). If the Pi's IP changes, the citation links break and the
RAG service cannot reach kiwix. Update `KIWIX_PUBLIC_URL` in `compose/.env`
whenever the Pi's IP changes.

### Firewall (Pi)

Allow kiwix access from the laptop only:

```bash
sudo ufw allow from <LAPTOP-IP> to any port 8081
```

Do not open port 8081 to the public internet.

### Latency

The RAG service fetches article text from kiwix over the LAN during indexing.
On a Gigabit home network this is fast enough to be imperceptible. On Wi-Fi,
indexing a large bundle may take longer—use Ethernet on the Pi if possible.

---

## Port summary

| Machine | Service | Port | Bound to |
|---------|---------|------|----------|
| Laptop (AI node) | Landing page | 8080 | 127.0.0.1 |
| Laptop (AI node) | RAG service | 8000 | 127.0.0.1 |
| Laptop (AI node) | Open WebUI | 3000 | 127.0.0.1 |
| Laptop (AI node) | Ollama | 11434 | 127.0.0.1 |
| Pi (archive node) | kiwix-serve | 8081 | 0.0.0.0 (LAN) |

The Pi's kiwix port is the only service exposed beyond the local machine, and
only to the LAN, not the public internet.

---

## Troubleshooting

### Citations load a "connection refused" page

The citation URL contains the Pi's IP from when the index was built. If the
Pi's IP has changed:

1. Update `KIWIX_PUBLIC_URL` in the laptop's `compose/.env`.
2. Re-run the RAG indexer to rebuild citation URLs:

```bash
docker compose exec rag python indexer.py --zim-dir /data --index-dir /index --ollama-url http://ollama:11434 --force
```

### RAG returns "no sources found" for everything

Check that kiwix is reachable from inside the RAG container:

```bash
docker compose exec rag curl -sf http://<ARCHIVE-NODE-IP>:8081/ > /dev/null && echo "OK"
```

If this fails, kiwix is not accessible on the LAN. Review the Pi's firewall
and the `KIWIX_BIND` setting.

### NFS mount disappears after reboot

Check `/etc/fstab` on the laptop and that the `_netdev` option is present.
Ensure the Pi is up before the laptop tries to mount:

```bash
sudo systemctl enable nfs-client.target
```

### Index is stale after ZIM update

Re-run the indexer after adding or replacing ZIM files:

```bash
docker compose exec rag python indexer.py --zim-dir /data --index-dir /index
```

---

## What is next

- For opt-in LAN access to the landing page and WebUI, see
  `docs/deployment/lan-access.md`.
- For the Pi text-only (all-in-one) pattern, see
  `docs/deployment/pi-text-only.md`.
