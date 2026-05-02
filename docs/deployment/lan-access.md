# LAN access (opt-in)

By default, AllArkive binds all services to `127.0.0.1` — nothing is
reachable outside the machine it runs on. This page documents how to
enable access from other devices on your local network.

**This is opt-in and not the default for a reason.** Read the risk section
before proceeding.

---

## When you might want this

- You run AllArkive on a home server or NAS and want to reach it from a
  laptop or tablet on the same network.
- You have AllArkive on a Raspberry Pi (archive-only or full stack) and
  want other household devices to use it.
- You want to share access with one other trusted person on the same LAN.

---

## When you probably do not want this

- You want to access AllArkive from outside your home network (the public
  internet). That is a different setup and requires significantly more
  security consideration than this guide covers. It is out of scope for v0.1.
- You are on a shared or untrusted network (office, coffee shop, hotel WiFi).
  Do not expose AllArkive on those networks without a VPN.

---

## The risk

Once a service binds to `0.0.0.0` instead of `127.0.0.1`, any device on
the same network segment can reach it. On a home network with a router that
separates LAN from internet, this is usually acceptable. On a network you
do not control, it is not.

Open WebUI has no login by default (`WEBUI_AUTH=false` in the default
config). Anyone who can reach the port can use the AI. If that is a concern,
enable authentication before exposing it.

---

## Option A: expose only the landing page (recommended)

The landing page is a static site. It does not run AI queries directly —
it links to the other services. Exposing only port 8080 behind a reverse
proxy is the lowest-risk option.

### Setup with Caddy (simplest)

[Caddy](https://caddyserver.com/) handles TLS automatically with a
self-signed certificate for LAN use.

1. Install Caddy on the AllArkive host:

   ```bash
   # Debian/Ubuntu:
   sudo apt install -y debian-keyring debian-archive-keyring apt-transport-https curl
   curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' \
     | sudo gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
   curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' \
     | sudo tee /etc/apt/sources.list.d/caddy-stable.list
   sudo apt update && sudo apt install caddy
   ```

2. Create `/etc/caddy/Caddyfile`:

   ```
   http://0.0.0.0:9080 {
       reverse_proxy 127.0.0.1:8080
   }
   ```

   This binds Caddy to port 9080 on all interfaces and forwards to the
   landing page on localhost. Using a non-standard port reduces accidental
   exposure and avoids conflicts.

3. Start Caddy:

   ```bash
   sudo systemctl enable --now caddy
   ```

4. On other devices, visit `http://<host-ip>:9080`.
   Find the host IP: `ip addr show | grep 'inet '`.

### Setup with nginx

If you prefer nginx:

```bash
sudo apt install -y nginx
```

Create `/etc/nginx/sites-available/allarkive`:

```nginx
server {
    listen 0.0.0.0:9080;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

Enable it:

```bash
sudo ln -s /etc/nginx/sites-available/allarkive /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

---

## Option B: expose the full stack with authentication

If you want the chat interface (Open WebUI on port 3000) accessible from
other devices, enable authentication first, then expose it via a reverse proxy.

### Step 1: enable Open WebUI authentication

In `compose/.env`:

```bash
WEBUI_AUTH=true
WEBUI_ENABLE_SIGNUP=false
```

Restart the stack:

```bash
cd compose/ && docker compose up -d open-webui
```

On first load, you will be prompted to create an admin account. Do this
from localhost before exposing the port.

### Step 2: add basic auth in the reverse proxy (belt and braces)

Even with Open WebUI's built-in auth, adding HTTP basic auth at the proxy
layer means an attacker needs two credentials, not one.

With Caddy (`/etc/caddy/Caddyfile`):

```
http://0.0.0.0:9080 {
    basicauth /* {
        alice $2a$14$...  # bcrypt hash — generate with: caddy hash-password
    }
    reverse_proxy 127.0.0.1:3000
}
```

Generate a password hash:

```bash
caddy hash-password
# Paste the hash into Caddyfile
```

With nginx (`/etc/nginx/sites-available/allarkive`):

```nginx
server {
    listen 0.0.0.0:9080;

    auth_basic "AllArkive";
    auth_basic_user_file /etc/nginx/.htpasswd;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
    }
}
```

Create the password file:

```bash
sudo apt install -y apache2-utils
sudo htpasswd -c /etc/nginx/.htpasswd alice
```

### Step 3: also expose kiwix-serve (optional)

If you want archive search from other devices too, add a second proxy block
for port 8081, or extend the existing block with a `/archive/` path.

---

## Firewall rules

If you use `ufw`:

```bash
# Allow your chosen proxy port from LAN only (e.g. 192.168.1.0/24):
sudo ufw allow from 192.168.1.0/24 to any port 9080
sudo ufw deny 9080
```

Replace `192.168.1.0/24` with your actual LAN subnet. This blocks anyone
outside your LAN subnet from reaching the proxy port even if the firewall
is on a machine with a public IP.

---

## Updating `compose/.env` for LAN use

The RAG citation links in model responses include the kiwix-serve URL.
By default this is `http://127.0.0.1:8081`, which only works on the
AllArkive host itself.

If you want citations to be clickable from other devices:

```bash
# Replace with the AllArkive host's LAN IP or hostname:
KIWIX_PUBLIC_URL=http://192.168.1.42:8081
```

Or, if you are proxying kiwix-serve through the same reverse proxy:

```bash
KIWIX_PUBLIC_URL=http://192.168.1.42:9080/archive
```

Restart the RAG service after changing this:

```bash
cd compose/ && docker compose restart rag
```

---

## Security posture summary

After enabling LAN access with the steps above:

| What changed | Risk | Mitigation |
|---|---|---|
| Landing page reachable on LAN | Low | Static HTML, no auth needed |
| Open WebUI reachable on LAN | Medium | Enable `WEBUI_AUTH=true`; add proxy basic auth |
| Kiwix reachable on LAN | Low | Read-only archive; no auth needed |
| Ollama API reachable on LAN | High if exposed | Do not expose directly; keep behind proxy |

**Do not expose Ollama's port (11434) directly to the LAN.** The Ollama API
has no built-in authentication and would allow anyone on your network to
run arbitrary models. All AI requests should go through Open WebUI or the
RAG service, both of which can be protected.

---

## This is not a guide to internet-facing deployment

Exposing AllArkive on the public internet requires:
- A real TLS certificate (Let's Encrypt or similar)
- Fail2ban or rate limiting to slow brute-force attacks
- Careful review of which ports are exposed
- Ongoing security updates

This is documented as out of scope for v0.1. If you need it, start with
the Caddy or nginx documentation, then layer AllArkive's services behind
a fully hardened reverse proxy configuration.
