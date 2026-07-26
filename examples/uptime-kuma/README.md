# Example: Uptime Kuma

Self-hosted uptime monitoring with a public status page.
No extra files needed — everything is self-contained in the image.

## Files to place in the Dockge stack folder

```
/opt/stacks/uptime-kuma/
└── docker-compose.yml   ← home server stack (only file needed)
```

## Quick Start (Home Server)

```bash
docker compose up -d
# Open http://127.0.0.1:3001 and complete the setup wizard
docker logs uptime-kuma -f
```

## Notes

- Data is persisted in the named volume `uptime-kuma-data`.
- Add monitors for all your exposed services after first login.
- Notifications: Telegram, Discord, Slack, email, and 90+ others.
- You can share a public status page without exposing the admin UI.

## VPS Configuration

**Socat bridge** — [`cgnat/vps/docker-compose.yml`](../../vps/docker-compose.yml)
```yaml
# Service name: socat-uptime-kuma
# Forwards VPS proxy network :3001 → WireGuard 10.8.0.2:3001
socat-uptime-kuma:
  image: alpine/socat:latest
  command: TCP4-LISTEN:3001,fork,reuseaddr TCP4:10.8.0.2:3001
  networks: [proxy]
```

**Traefik router + service** — [`cgnat/vps/traefik/dynamic.yml`](../../vps/traefik/dynamic.yml)
```yaml
routers:
  uptime-kuma:
    rule: "Host(`status.xore.rocks`)"
    entryPoints: [websecure]
    service: uptime-kuma
    tls:
      options: modern
    middlewares: [security-headers, rate-limit]

services:
  uptime-kuma:
    loadBalancer:
      servers:
        - url: "http://socat-uptime-kuma:3001"
      passHostHeader: true
```

**Cloudflare DNS:** A record → VPS IP, **Proxied 🟠**

> **Tip:** Uptime Kuma uses WebSockets for live updates. In Cloudflare, make sure **WebSockets** is enabled under Network settings (it is by default on all plans).
