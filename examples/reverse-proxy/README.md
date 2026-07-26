# Example: Reverse Proxy (Any LAN Host)

Forward traffic to any service on your LAN — no app container needed, socat only.
Useful for Home Assistant, Proxmox, Synology NAS, cameras, or any service you can't or don't want to Dockerize.

## Files to place in the Dockge stack folder

```
/opt/stacks/reverse-proxy/
└── docker-compose.yml   ← edit the socat command to point to your LAN host
```

## Quick Start (Home Server)

1. Edit `docker-compose.yml` — replace `192.168.1.10:8123` with your upstream host and port.
2. `docker compose up -d`
3. Test: from the VPS, `curl http://10.8.0.2:<port>`

## Notes

- The `bind=10.8.0.2` makes socat listen only on the WireGuard interface, not LAN.
- For UDP services (e.g. game servers), change `TCP4` to `UDP4` in both the socat command and the Traefik entrypoint.
- You can run multiple instances: just copy the socat service block with a different name and port.

## VPS Configuration

This example uses the generic `socat-upstream` bridge for a Home Assistant setup.
Edit the port (`8123`) to match your actual service.

**Socat bridge** — [`cgnat/vps/docker-compose.yml`](../../vps/docker-compose.yml)
```yaml
# Service name: socat-upstream
# Forwards VPS proxy network :8123 → WireGuard 10.8.0.2:8123
socat-upstream:
  image: alpine/socat:latest
  command: TCP4-LISTEN:8123,fork,reuseaddr TCP4:10.8.0.2:8123
  networks: [proxy]
```

**Traefik router + service** — [`cgnat/vps/traefik/dynamic.yml`](../../vps/traefik/dynamic.yml)
```yaml
routers:
  upstream:
    rule: "Host(`ha.xore.rocks`)"
    entryPoints: [websecure]
    service: upstream
    tls:
      options: modern
    middlewares: [security-headers, rate-limit]

services:
  upstream:
    loadBalancer:
      servers:
        - url: "http://socat-upstream:8123"
      passHostHeader: true
```

**Cloudflare DNS:** A record → VPS IP, **Proxied 🟠**

> **Game servers:** Use the `socat-minecraft` / `socat-game-udp` services in the VPS compose instead, with **DNS-only (grey cloud)** Cloudflare records.
