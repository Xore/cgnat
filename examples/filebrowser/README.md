# Example: File Browser

Web-based file manager — browse, upload, download, rename files via HTTPS.
No extra files needed — everything is self-contained in the image.

## Files to place in the Dockge stack folder

```
/opt/stacks/filebrowser/
├── docker-compose.yml   ← home server stack (only file needed)
└── data/                ← created automatically; files you expose via the UI
```

## Quick Start (Home Server)

```bash
docker compose up -d
# Open http://127.0.0.1:8070
# Default login: admin / admin  — CHANGE THIS IMMEDIATELY
docker logs filebrowser -f
```

## Notes

- **Change the default password** on first login — the UI will prompt you.
- `./data` is the root directory exposed in the UI. Mount additional paths as extra volumes if needed.
- DB (users, settings) is persisted in the named volume `filebrowser-db`.

## VPS Configuration

**Socat bridge** — [`cgnat/vps/docker-compose.yml`](../../vps/docker-compose.yml)
```yaml
# Service name: socat-filebrowser
# Forwards VPS proxy network :8070 → WireGuard 10.8.0.2:8070
socat-filebrowser:
  image: alpine/socat:latest
  command: TCP4-LISTEN:8070,fork,reuseaddr TCP4:10.8.0.2:8070
  networks: [proxy]
```

**Traefik router + service** — [`cgnat/vps/traefik/dynamic.yml`](../../vps/traefik/dynamic.yml)
```yaml
routers:
  filebrowser:
    rule: "Host(`files.xore.rocks`)"
    entryPoints: [websecure]
    service: filebrowser
    tls:
      options: modern
    middlewares: [security-headers, rate-limit]

services:
  filebrowser:
    loadBalancer:
      servers:
        - url: "http://socat-filebrowser:8070"
      passHostHeader: true
```

**Cloudflare DNS:** A record → VPS IP, **Proxied 🟠**
