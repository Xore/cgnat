# CGNAT VPS Gateway — Complete Setup Guide

A step-by-step guide to expose home server services through a VPS using WireGuard, Traefik, socat, and Cloudflare.

> All referenced config files and example code live in the same repo under `cgnat/`.

> **Current deployment layout (2026):** the VPS project runs with plain Docker
> Compose at `/root/vps/docker-compose.yml`. Home workloads use separate Dockge
> stacks under `/opt/stacks/`; the honeypot's authoritative file is
> `/opt/stacks/honeypot-stack/compose.yml`. Older generic examples below should
> be adapted into an individual home stack rather than a monolithic
> `home-server` directory.

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [VPS Setup](#2-vps-setup)
3. [Home Server Setup](#3-home-server-setup)
4. [Cloudflare Configuration](#4-cloudflare-configuration)
5. [Full VPS Hardening](#5-full-vps-hardening)
6. [Tutorial: Adding a New Docker Container](#6-tutorial-adding-a-new-docker-container)
7. [Tutorial: Exposing a Custom Python Script](#7-tutorial-exposing-a-custom-python-script)
8. [Tutorial: Forwarding to Another LAN Host](#8-tutorial-forwarding-to-another-lan-host)
9. [Tutorial: Game Server Port Forwarding](#9-tutorial-game-server-port-forwarding)
10. [Troubleshooting](#10-troubleshooting)
11. [Quick Reference Cheatsheet](#11-quick-reference-cheatsheet)

---

## 1. Architecture Overview

The home server sits behind CGNAT (no public IP). A VPS with a public IP acts as the gateway. WireGuard creates an encrypted tunnel between them. Traefik on the VPS terminates TLS from Cloudflare and routes traffic through socat bridges over the WireGuard tunnel to services on the home server.

### High-Level Flow

```
┌──────────┐     ┌────────────┐     ┌─────────────────────────────────┐     ┌─────────────────────────────────┐
│  Browser  │────▶│ Cloudflare │────▶│           VPS                  │────▶│        Home Server              │
│           │     │  (WAF/CDN) │     │  Traefik :443 → socat → wg0    │     │  wg0 → socat → App / LAN Host  │
└──────────┘     └────────────┘     └─────────────────────────────────┘     └─────────────────────────────────┘
```

### Detailed Traffic Flow

```
Internet
  │
  ▼
Cloudflare (proxied A record, Full Strict SSL, WAF, Bot Fight Mode)
  │
  ▼ HTTPS :443
VPS ─────────────────────────────────────────────────
  │
  ├─ Traefik container (proxy network, port 443)
  │    │
  │    ├─ Host(`static.xore.rocks`)  → socat-static:8080
  │    ├─ Host(`media.xore.rocks`)   → socat-jellyfin:8096
  │    └─ Host(`api.xore.rocks`)     → socat-myapi:5000
  │
  ├─ socat-* containers (proxy network)
  │    └─ TCP4-LISTEN:<port> → TCP4:10.8.0.2:<port>
  │
  └─ WireGuard wg0 (10.8.0.1, host network)
       │
       │  encrypted tunnel over public internet
       ▼
Home Server ────────────────────────────────────────────
  │
  ├─ WireGuard wg0 (10.8.0.2)  ← PersistentKeepalive=25 (critical!)
  │
  ├─ socat-* containers (host network, bind=10.8.0.2)
  │    ├─ :8080 → 127.0.0.1:8080  (nginx)
  │    ├─ :8096 → 127.0.0.1:8096  (jellyfin)
  │    └─ :5000 → 127.0.0.1:5000  (python api)
  │
  └─ Application containers (localhost)
       ├─ nginx-static :8080
       ├─ jellyfin :8096
       └─ myapi :5000
```

### Port Mapping Summary

| Domain | Traefik Router | VPS socat port | WG Tunnel | Home socat port | Target |
|--------|---------------|----------------|-----------|-----------------|--------|
| static.xore.rocks | static-site | 8080 | 10.8.0.1→10.8.0.2 | 8080 | 127.0.0.1:8080 (nginx) |
| media.xore.rocks | jellyfin | 8096 | 10.8.0.1→10.8.0.2 | 8096 | 127.0.0.1:8096 (jellyfin) |
| api.xore.rocks | myapi | 5000 | 10.8.0.1→10.8.0.2 | 5000 | 127.0.0.1:5000 (python api) |

---

## 2. VPS Setup

### 2.1 System Prep

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y wireguard wireguard-tools curl ufw fail2ban unattended-upgrades ca-certificates
```

> **Note:** Do **not** install `docker.io` or `docker-compose` from the Ubuntu repos — they are outdated. Follow section 2.2 to install the official Docker Engine.

### 2.2 Install Docker Engine (Official Method)

> This is the correct way to install Docker with the Compose plugin. Source: [docs.docker.com/engine/install/ubuntu](https://docs.docker.com/engine/install/ubuntu/)

**Step 1 — Remove any conflicting packages:**

```bash
sudo apt remove $(dpkg --get-selections docker.io docker-compose docker-compose-v2 docker-doc podman-docker containerd runc 2>/dev/null | cut -f1) 2>/dev/null || true
```

**Step 2 — Add Docker's official GPG key and apt repository:**

```bash
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update
```

**Step 3 — Install Docker Engine + Compose plugin:**

```bash
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

**Step 4 — Verify:**

```bash
sudo docker run hello-world
docker compose version
```

**Step 5 — Allow your user to run Docker without sudo (optional but recommended):**

```bash
sudo usermod -aG docker $USER
# Log out and back in for this to take effect
newgrp docker
```

**Upgrading Docker later:**

```bash
sudo apt update && sudo apt upgrade docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

### 2.3 WireGuard (Server Role)

See template: [`cgnat/wireguard/wg0-vps.conf.example`](../wireguard/wg0-vps.conf.example)

```bash
sudo mkdir -p /etc/wireguard && cd /etc/wireguard
wg genkey | sudo tee privatekey | wg pubkey | sudo tee publickey
sudo chmod 600 privatekey && sudo chmod 644 publickey
wg genpsk | sudo tee preshared.key && sudo chmod 600 preshared.key
```

Copy and fill in the template:

```bash
cp cgnat/wireguard/wg0-vps.conf.example /etc/wireguard/wg0.conf
sudo nano /etc/wireguard/wg0.conf
```

```bash
sudo wg-quick up wg0
sudo systemctl enable wg-quick@wg0
```

### 2.4 Cloudflare Origin Certificate

1. Cloudflare Dashboard → SSL/TLS → Origin Server → Create Certificate
2. RSA 2048, `*.xore.rocks, xore.rocks`, 15-year validity
3. Save as:

```bash
mkdir -p /root/vps/traefik/certs
nano /root/vps/traefik/certs/origin.pem
nano /root/vps/traefik/certs/origin-key.pem
chmod 644 /root/vps/traefik/certs/origin.pem
chmod 600 /root/vps/traefik/certs/origin-key.pem
```

### 2.5 VPS Docker Stack

See: [`cgnat/vps/docker-compose.yml`](../vps/docker-compose.yml)

```bash
cd /root/vps && docker compose -f docker-compose.yml up -d
```

---

## 3. Home Server Setup

### 3.1 Install Docker Engine

Follow the exact same steps as [Section 2.2](#22-install-docker-engine-official-method) on the home server.

### 3.2 WireGuard (Client Role)

Use the peer values from [`cgnat/wireguard/wg0-vps.conf.example`](../wireguard/wg0-vps.conf.example)
to create the home client's `/etc/wireguard/wg0.conf`.

```bash
sudo mkdir -p /etc/wireguard && cd /etc/wireguard
wg genkey | sudo tee privatekey | wg pubkey | sudo tee publickey
sudo chmod 600 privatekey
```

```bash
sudo nano /etc/wireguard/wg0.conf   # fill in keys
```

```bash
sudo wg-quick up wg0
sudo systemctl enable wg-quick@wg0
sudo wg show && ping 10.8.0.1
```

> **Critical:** `PersistentKeepalive = 25` must be set on the home server. Without it, CGNAT NAT mappings expire and the tunnel dies.

### 3.3 Home Server Docker Stack

Deploy the selected folder from [`cgnat/examples/`](../examples/) as its own
Dockge stack under `/opt/stacks/<name>`. For the honeypot use
`/opt/stacks/honeypot-stack/compose.yml` exactly.

### 3.4 Verify End-to-End

```bash
curl http://127.0.0.1:8080           # local nginx
curl http://10.8.0.2:8080            # through WireGuard (run on VPS)
curl https://static.xore.rocks       # full end-to-end
```

---

## 4. Cloudflare Configuration

### 4.1 DNS Records

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| A | static | `<VPS_PUBLIC_IP>` | ✅ Proxied |
| A | api | `<VPS_PUBLIC_IP>` | ✅ Proxied |

### 4.2 SSL/TLS Settings

| Setting | Value |
|---------|-------|
| SSL Mode | Full (Strict) |
| Minimum TLS | TLS 1.2 |
| Always Use HTTPS | Enabled |
| TLS 1.3 | Enabled |

### 4.3 Security

| Setting | Value |
|---------|-------|
| WAF Managed Ruleset | Enabled |
| Bot Fight Mode | Enabled |
| Browser Integrity Check | Enabled |

---

## 5. Full VPS Hardening

### 5.1 SSH

```
PasswordAuthentication no
PermitRootLogin no
MaxAuthTries 3
Port 2222
```

```bash
sudo systemctl restart sshd
```

### 5.2 UFW

```bash
sudo ufw reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 2222/tcp
sudo ufw allow 51820/udp

for ip in $(curl -s https://www.cloudflare.com/ips-v4); do
    sudo ufw allow from $ip to any port 443 proto tcp
done

sudo ufw enable
```

### 5.3 Fail2ban

```ini
[sshd]
enabled = true
port = 2222
maxretry = 3
bantime = 1d
```

```bash
sudo systemctl enable --now fail2ban
```

### 5.4 Kernel Hardening (sysctl)

```bash
sudo tee /etc/sysctl.d/99-vps-hardening.conf <<'EOF'
# IP forwarding (required for WireGuard)
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.tcp_syncookies = 1

# Docker bridge support
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1

# Network performance
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.ip_local_port_range = 1024 65535

# File handles (needed for many containers)
fs.file-max = 2097152
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288

# Memory
vm.swappiness = 10
vm.max_map_count = 262144
EOF

sudo sysctl -p /etc/sysctl.d/99-vps-hardening.conf
```

### 5.5 Docker Daemon — Hardening + Performance Tuning

This section combines security hardening and production performance tuning into a single `daemon.json`.

#### Security Flags

| Flag | Purpose |
|------|---------|
| `icc: false` | Disable inter-container communication by default |
| `no-new-privileges: true` | Prevent containers from gaining extra privileges via setuid/setgid |
| `userns-remap: default` | Remap container root to unprivileged host user (rootless-like isolation) |
| `live-restore: true` | Keep containers running during daemon restarts/upgrades |

#### Performance Flags

| Flag | Value | Purpose |
|------|-------|---------|
| `storage-driver` | `overlay2` | Best performance on modern Linux kernels |
| `log-driver` | `local` | More efficient than `json-file`; compressed, binary format |
| `userland-proxy` | `false` | Use iptables DNAT instead of userland proxy for port forwarding |
| `exec-opts cgroupdriver` | `systemd` | Align with systemd cgroups — avoids double cgroup management |
| `max-concurrent-downloads` | `10` | Faster parallel image pulls (default: 3) |
| `max-concurrent-uploads` | `10` | Faster parallel pushes |
| `features.buildkit` | `true` | Enable BuildKit for faster, cache-efficient builds |

#### `/etc/docker/daemon.json`

```json
{
  "storage-driver": "overlay2",

  "log-driver": "local",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3",
    "compress": "true"
  },

  "icc": false,
  "no-new-privileges": true,
  "live-restore": true,
  "userland-proxy": false,
  "shutdown-timeout": 15,

  "exec-opts": ["native.cgroupdriver=systemd"],

  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 10,

  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 65535,
      "Soft": 65535
    }
  },

  "features": {
    "buildkit": true
  }
}
```

Apply:

```bash
sudo mkdir -p /etc/docker
sudo nano /etc/docker/daemon.json    # paste config above
sudo systemctl restart docker
docker info | grep -E "Storage Driver|Logging Driver|Cgroup Driver"
```

#### systemd Service Override (optional, for high-load servers)

```bash
sudo mkdir -p /etc/systemd/system/docker.service.d
sudo tee /etc/systemd/system/docker.service.d/override.conf <<'EOF'
[Service]
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TimeoutStartSec=300
Restart=always
RestartSec=5
EOF

sudo systemctl daemon-reload && sudo systemctl restart docker
```

#### System-level File Descriptor Limits

```bash
sudo tee -a /etc/security/limits.conf <<'EOF'
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF
```

#### UFW + Docker Compatibility Note

> Docker manipulates iptables directly and **bypasses UFW rules for exposed container ports**. To keep UFW in control, either:
> - Bind ports to `127.0.0.1` (e.g. `"127.0.0.1:8080:80"`) so they're not exposed on public interfaces, **or**
> - Add rules to the `DOCKER-USER` iptables chain directly for ports that must be exposed.
>
> In this setup all service ports bind to `127.0.0.1` or `10.8.0.2` (WireGuard), so UFW rules remain effective.

### 5.6 Automatic Security Updates

```bash
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

`/etc/apt/apt.conf.d/50unattended-upgrades` — ensure this is enabled:

```
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
```

### 5.7 Hardening Checklist

| Item | Done |
|------|------|
| SSH key-only, root disabled, port changed | ☐ |
| UFW: only Cloudflare IPs on :443 | ☐ |
| Fail2ban configured | ☐ |
| Kernel hardening (sysctl) applied | ☐ |
| Automatic security updates enabled | ☐ |
| Docker installed via official apt repo | ☐ |
| Docker daemon.json configured | ☐ |
| Docker icc=false, no-new-privileges=true | ☐ |
| Docker userland-proxy=false | ☐ |
| Docker log-driver=local with size limits | ☐ |
| BuildKit enabled | ☐ |
| WireGuard keys chmod 600 | ☐ |
| WireGuard pre-shared key set | ☐ |
| PersistentKeepalive=25 on home server | ☐ |
| Traefik dashboard disabled | ☐ |
| TLS 1.3 minimum | ☐ |
| Cloudflare Full (Strict) SSL | ☐ |
| Cloudflare WAF + Bot Fight Mode | ☐ |
| Service ports bound to 127.0.0.1 or WG IP | ☐ |

---

## 6. Tutorial: Adding a New Docker Container

**Example: Jellyfin on port 8096 → `media.xore.rocks`**

### Step 1 — Home Server: App + socat

Add to the selected home stack's Compose file:

```yaml
  jellyfin:
    image: jellyfin/jellyfin:latest
    container_name: jellyfin
    restart: unless-stopped
    ports:
      - "127.0.0.1:8096:8096"
    volumes:
      - ./jellyfin/config:/config
      - /mnt/media:/media

  socat-jellyfin:
    image: alpine/socat:latest
    container_name: socat-jellyfin
    restart: unless-stopped
    command: TCP4-LISTEN:8096,bind=10.8.0.2,fork,reuseaddr TCP4:127.0.0.1:8096
    network_mode: host
```

### Step 2 — VPS: socat Bridge

Add to `cgnat/vps/docker-compose.yml`:

```yaml
  socat-jellyfin:
    image: alpine/socat:latest
    container_name: socat-jellyfin
    restart: unless-stopped
    command: TCP4-LISTEN:8096,fork,reuseaddr TCP4:10.8.0.2:8096
    networks:
      - proxy
```

### Step 3 — VPS: Traefik Router

Add to `cgnat/vps/traefik/dynamic.yml` under `http.routers` and `http.services`:

```yaml
    jellyfin:
      rule: "Host(`media.xore.rocks`)"
      entryPoints: [websecure]
      service: jellyfin
      tls:
        options: modern
      middlewares: [security-headers, rate-limit]
```

```yaml
    jellyfin:
      loadBalancer:
        servers:
          - url: "http://socat-jellyfin:8096"
```

### Step 4 — Cloudflare DNS

`A` record: `media` → `<VPS_IP>` (✅ Proxied)

### Flow Diagram

```
Browser → https://media.xore.rocks
  ▼ Cloudflare WAF + TLS
  ▼ VPS Traefik → socat-jellyfin:8096
  ▼ WireGuard tunnel → 10.8.0.2:8096
  ▼ Home socat → 127.0.0.1:8096 → Jellyfin
```

---

## 7. Tutorial: Exposing a Custom Python Script

**Example: Flask API on port 5000 → `api.xore.rocks`**

A working example lives in [`cgnat/examples/python-api/`](../examples/python-api/).

### The Example API

File: [`cgnat/examples/python-api/app.py`](../examples/python-api/app.py)

```python
import datetime
from flask import Flask, jsonify

app = Flask(__name__)

@app.route("/")
def hello():
    return jsonify({
        "message": "Hello, World!",
        "status": "ok"
    })

@app.route("/health")
def health():
    return jsonify({
        "status": "healthy",
        "timestamp": datetime.datetime.utcnow().isoformat() + "Z"
    })

if __name__ == "__main__":
    # Development only — use gunicorn in production (see Dockerfile)
    app.run(host="0.0.0.0", port=5000, debug=False)
```

The Dockerfile runs the app with Gunicorn (production WSGI server):

```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
EXPOSE 5000
CMD ["gunicorn", "--bind", "0.0.0.0:5000", "--workers", "2", "--access-logfile", "-", "app:app"]
```

### Step 1 — Copy the Example to Your Home Server

```bash
cp -r cgnat/examples/python-api /opt/stacks/myapi
```

### Step 2 — Add to Home Server Docker Compose

Edit `/opt/stacks/myapi/docker-compose.yml` (or the filename already configured
for that Dockge stack):

```yaml
  myapi:
    build: ./myapi
    container_name: myapi
    restart: unless-stopped
    ports:
      - "127.0.0.1:5000:5000"

  socat-myapi:
    image: alpine/socat:latest
    container_name: socat-myapi
    restart: unless-stopped
    command: TCP4-LISTEN:5000,bind=10.8.0.2,fork,reuseaddr TCP4:127.0.0.1:5000
    network_mode: host
```

```bash
cd /opt/stacks/myapi && docker compose up -d --build
```

### Step 3 — VPS: socat Bridge

Add to `cgnat/vps/docker-compose.yml`:

```yaml
  socat-myapi:
    image: alpine/socat:latest
    container_name: socat-myapi
    restart: unless-stopped
    command: TCP4-LISTEN:5000,fork,reuseaddr TCP4:10.8.0.2:5000
    networks:
      - proxy
```

```bash
cd /root/vps && docker compose -f docker-compose.yml up -d
```

### Step 4 — VPS: Traefik Router

Add to `cgnat/vps/traefik/dynamic.yml`:

```yaml
    myapi:
      rule: "Host(`api.xore.rocks`)"
      entryPoints: [websecure]
      service: myapi
      tls:
        options: modern
      middlewares: [security-headers, rate-limit]
```

```yaml
    myapi:
      loadBalancer:
        servers:
          - url: "http://socat-myapi:5000"
```

### Step 5 — Cloudflare DNS

`A` record: `api` → `<VPS_IP>` (✅ Proxied)

### Step 6 — Verify

```bash
# Local
curl http://127.0.0.1:5000/
curl http://127.0.0.1:5000/health

# Through tunnel (from VPS)
curl http://10.8.0.2:5000/health

# End-to-end
curl https://api.xore.rocks/
curl https://api.xore.rocks/health
```

**Expected responses:**

```json
// GET /
{ "message": "Hello, World!", "status": "ok" }

// GET /health
{ "status": "healthy", "timestamp": "2026-07-12T16:40:00Z" }
```

### Flow Diagram

```
Browser → https://api.xore.rocks/health
  ▼ Cloudflare WAF + TLS
  ▼ VPS Traefik → socat-myapi:5000
  ▼ WireGuard tunnel → 10.8.0.2:5000
  ▼ Home socat → 127.0.0.1:5000 → Gunicorn → Flask
  ▼ { "status": "healthy", "timestamp": "..." }
```

---

## 8. Tutorial: Forwarding to Another LAN Host

**Example: Service on `192.168.42.200:4444` → `example.xore.rocks`**

The only difference from a local container: socat target is the LAN IP, not `127.0.0.1`.

### Home Server socat

```yaml
  socat-example:
    image: alpine/socat:latest
    container_name: socat-example
    restart: unless-stopped
    command: TCP4-LISTEN:4444,bind=10.8.0.2,fork,reuseaddr TCP4:192.168.42.200:4444
    network_mode: host
```

> `network_mode: host` gives the container access to the home server's LAN interface, so it can reach `192.168.42.200`.

### Key Difference

| Scenario | Home socat Target |
|----------|------------------|
| Container on home server | `TCP4:127.0.0.1:<port>` |
| Another machine on LAN | `TCP4:192.168.42.200:<port>` |

### Flow Diagram

```
Browser → https://example.xore.rocks
  ▼ Cloudflare → VPS Traefik → socat-example:4444
  ▼ WireGuard tunnel → 10.8.0.2:4444
  ▼ Home socat (host network) → 192.168.42.200:4444
  ▼ Service on another LAN machine
```

---

## 9. Tutorial: Game Server Port Forwarding

> Game servers use raw TCP/UDP — they **cannot** go through Cloudflare proxy or Traefik. Use socat with a directly exposed VPS port and a **gray-cloud** DNS record.

### Protocol Compatibility

| Protocol | Traefik | Cloudflare Proxy | socat direct |
|----------|---------|------------------|--------------|
| HTTPS | ✅ | ✅ | — |
| Raw TCP (Minecraft :25565) | ⚠️ | ❌ | ✅ |
| UDP (CS2, Source :27015) | ❌ | ❌ | ✅ |

### Step 1 — Home Server: Game + socat

**TCP (Minecraft):**

```yaml
  minecraft:
    image: itzg/minecraft-server:latest
    container_name: minecraft
    restart: unless-stopped
    environment:
      EULA: "TRUE"
    ports:
      - "127.0.0.1:25565:25565"
    volumes:
      - ./minecraft/data:/data

  socat-minecraft:
    image: alpine/socat:latest
    container_name: socat-minecraft
    restart: unless-stopped
    command: TCP4-LISTEN:25565,bind=10.8.0.2,fork,reuseaddr TCP4:127.0.0.1:25565
    network_mode: host
```

**UDP (CS2):**

```yaml
  socat-cs2:
    image: alpine/socat:latest
    container_name: socat-cs2
    restart: unless-stopped
    command: UDP4-LISTEN:27015,bind=10.8.0.2,fork,reuseaddr UDP4:127.0.0.1:27015
    network_mode: host
```

### Step 2 — VPS: socat With Exposed Port (No Traefik)

**TCP:**

```yaml
  socat-minecraft:
    image: alpine/socat:latest
    container_name: socat-minecraft
    restart: unless-stopped
    command: TCP4-LISTEN:25565,fork,reuseaddr TCP4:10.8.0.2:25565
    ports:
      - "25565:25565"
    networks:
      - proxy
```

**UDP:**

```yaml
  socat-cs2:
    image: alpine/socat:latest
    restart: unless-stopped
    command: UDP4-LISTEN:27015,fork,reuseaddr UDP4:10.8.0.2:27015
    ports:
      - "27015:27015/udp"
    networks:
      - proxy
```

### Step 3 — VPS Firewall

```bash
sudo ufw allow 25565/tcp
sudo ufw allow 27015/udp
```

### Step 4 — Cloudflare DNS (Gray Cloud!)

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| A | mc | `<VPS_IP>` | ❌ DNS only |

### Flow Diagram

```
Game Client → mc.xore.rocks:25565 (DNS only, no Cloudflare proxy)
  ▼ VPS public IP :25565 (UFW open, no Traefik)
  ▼ socat-minecraft → TCP4:10.8.0.2:25565
  ▼ WireGuard tunnel
  ▼ Home socat-minecraft → 127.0.0.1:25565 → Game server
```

### Web vs Game Side-by-Side

| | Web App | Game Server |
|-|---------|-------------|
| DNS | Orange cloud (Proxied) | Gray cloud (DNS only) |
| Traefik | ✅ Used | ❌ Bypassed |
| Cloudflare WAF | ✅ Active | ❌ Bypassed |
| VPS socat | No exposed port | Port exposed directly |
| UFW | :443 from CF IPs only | Port opened to world |
| Protocol | HTTPS | TCP or UDP |

---

## 10. Troubleshooting

### 502 Bad Gateway

```bash
docker ps | grep socat-<name>                          # container running?
docker exec traefik wget -qO- http://socat-<name>:<port> # traefik can reach it?
curl -v http://10.8.0.2:<port>                         # VPS can reach home?
sudo wg show                                           # tunnel up?
curl http://127.0.0.1:<port>                           # app running on home?
```

| Symptom | Fix |
|---------|-----|
| socat not on `proxy` network | Add `networks: [proxy]` |
| WireGuard no handshake | `wg-quick down wg0 && wg-quick up wg0` |
| Home socat wrong IP | Ensure `bind=10.8.0.2` + `network_mode: host` |

### Cloudflare Errors

| Code | Cause | Fix |
|------|-------|-----|
| 520 | Traefik misconfigured | `docker logs traefik` |
| 521 | Traefik not running | `docker compose up -d` |
| 522 | VPS unreachable | Check UFW |
| 525/526 | SSL cert issue | Verify/regenerate origin cert |

### Game Server Not Reachable

```bash
nc -zv <VPS_IP> 25565       # port open on VPS?
dig mc.xore.rocks           # returns VPS IP directly (not CF IP)?
sudo wg show                # tunnel up?
curl http://10.8.0.2:25565  # reachable through tunnel?
```

### Docker Daemon Issues

```bash
docker info                              # check storage driver, cgroup driver
journalctl -u docker.service --tail 30  # daemon logs
docker info --format '{{.Driver}}'      # storage driver
docker info --format '{{.LoggingDriver}}' # logging driver
```

---

## 11. Quick Reference Cheatsheet

### 4-Step Pattern

```
WEB APP                                  GAME SERVER
──────────────────────────────────────── ──────────────────────────────────────
1. Home: app + socat bind=10.8.0.2       1. Home: game + socat bind=10.8.0.2
2. VPS: socat → 10.8.0.2 (proxy net)    2. VPS: socat + exposed port
3. VPS: Traefik router + service         3. VPS: ufw allow <port>
4. CF: A record (orange cloud)           4. CF: A record (gray cloud!)
```

### socat Reference

| Location | Pattern |
|----------|---------|
| VPS (web) | `TCP4-LISTEN:<p>,fork,reuseaddr TCP4:10.8.0.2:<p>` |
| VPS (game TCP) | same + `ports: ["<p>:<p>"]` |
| VPS (game UDP) | `UDP4-LISTEN:<p>,fork,reuseaddr UDP4:10.8.0.2:<p>` + `ports: ["<p>:<p>/udp"]` |
| Home (local) | `TCP4-LISTEN:<p>,bind=10.8.0.2,fork,reuseaddr TCP4:127.0.0.1:<p>` |
| Home (LAN host) | `TCP4-LISTEN:<p>,bind=10.8.0.2,fork,reuseaddr TCP4:192.168.x.x:<p>` |
| Home (UDP) | `UDP4-LISTEN:<p>,bind=10.8.0.2,fork,reuseaddr UDP4:127.0.0.1:<p>` |

### Common Commands

```bash
# Docker
cd /root/vps && docker compose down && docker compose up -d
cd /opt/stacks/<name> && docker compose up -d
docker logs traefik --tail 30
docker info | grep -E "Storage|Logging|Cgroup"

# WireGuard
sudo wg show
sudo wg-quick down wg0 && sudo wg-quick up wg0

# UFW
sudo ufw status verbose

# Docker install / upgrade
sudo apt update && sudo apt upgrade docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```
