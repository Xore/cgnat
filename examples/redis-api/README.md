# Example: Flask + Redis Blog (Dockge / no Dockerfile)

The **xore//blog** system on a Flask backend with **Redis** storage. Same
frontend and REST API contract as every blog example in this folder — this one
keeps each post as a JSON string (`post:<id>`) plus a sorted-set index
(`posts:index`) scored by `createdAt` for ordering.

| Layer | Tech |
|---|---|
| Frontend | Shared xore//blog SPA (`static/` — vanilla JS, hash routing) |
| Backend | Flask 3 + Gunicorn |
| Storage | Redis 7 (JSON strings + sorted-set index, RDB persistence volume) |
| Admin auth | `X-Admin-Token` header, password from `ADMIN_PASSWORD` env |

## Files to place in the Dockge stack folder

```
/opt/stacks/redis-api/
├── docker-compose.yml   ← home server stack (redis + api + socat)
├── app.py               ← Flask app (API + serves static/)
├── gunicorn.conf.py     ← Gunicorn settings
└── static/              ← shared frontend (index.html, app.js, xore.css)
```

## Quick Start (Home Server)

```bash
docker compose up -d
curl http://127.0.0.1:5001/health
curl http://127.0.0.1:5001/api/posts
# then open http://127.0.0.1:5001 — admin panel under ADMIN (nav)
```

## API

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /api/posts | public | List published posts |
| GET | /api/posts/:id | public | Get single post |
| POST | /api/admin/login | public | Exchange password for token |
| GET | /api/admin/posts | admin | List all posts (incl. drafts) |
| POST | /api/admin/posts | admin | Create post |
| PUT | /api/admin/posts/:id | admin | Update post |
| DELETE | /api/admin/posts/:id | admin | Delete post |
| GET | /health | public | Health check (pings Redis, post count) |

## Notes

- Change **both** passwords in `docker-compose.yml`: Redis
  (`--requirepass changeme` + `REDIS_PASSWORD=changeme`) and the admin panel
  (`ADMIN_PASSWORD=change-me-redis`).
- Redis is not exposed to the host — only reachable within the Docker network.
- Named volume `redis-data` persists posts across restarts (RDB snapshots).
- Unlike the flat-file examples, Redis storage is safe for multiple Gunicorn
  workers.

## VPS Configuration

**Socat bridge** — [`cgnat/vps/docker-compose.yml`](../../vps/docker-compose.yml)
```yaml
# Service name: socat-redis-api
# Forwards VPS proxy network :5001 → WireGuard 10.8.0.2:5001
socat-redis-api:
  image: alpine/socat:latest
  command: TCP4-LISTEN:5001,fork,reuseaddr TCP4:10.8.0.2:5001
  networks: [proxy]
```

**Traefik router + service** — [`cgnat/vps/traefik/dynamic.yml`](../../vps/traefik/dynamic.yml)
```yaml
routers:
  redis-api:
    rule: "Host(`redis-api.xore.rocks`)"
    entryPoints: [websecure]
    service: redis-api
    tls:
      options: modern
    middlewares: [security-headers, rate-limit]

services:
  redis-api:
    loadBalancer:
      servers:
        - url: "http://socat-redis-api:5001"
      passHostHeader: true
```

**Cloudflare DNS:** A record → VPS IP, **Proxied 🟠**
