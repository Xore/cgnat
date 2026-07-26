# Example: Flask Blog (Python, Dockge / no Dockerfile)

The **xore//blog** system on a Flask + Gunicorn backend. Same frontend and REST
API contract as every blog example in this folder — this one stores posts in a
JSON flat file.

| Layer | Tech |
|---|---|
| Frontend | Shared xore//blog SPA (`static/` — vanilla JS, hash routing) |
| Backend | Flask 3 + Gunicorn (1 worker — flat-file consistency) |
| Storage | JSON flat file in a named volume (`/app/data/posts.json`) |
| Admin auth | `X-Admin-Token` header, password from `ADMIN_PASSWORD` env |

## Files to place in the Dockge stack folder

```
/opt/stacks/python-api/
├── docker-compose.yml   ← home server stack
├── app.py               ← Flask app (API + serves static/)
├── gunicorn.conf.py     ← Gunicorn settings
└── static/              ← shared frontend (index.html, app.js, xore.css)
```

## Quick Start (Home Server)

```bash
docker compose up -d
curl http://127.0.0.1:5000/health
curl http://127.0.0.1:5000/api/posts
# then open http://127.0.0.1:5000 — admin panel under ADMIN (nav)
```

Set the admin password in `docker-compose.yml` (`ADMIN_PASSWORD=change-me-py`).

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
| GET | /health | public | Health check (post count) |

## Notes

- Posts persist in the `blog-data` named volume; the repo stays clean.
- Gunicorn runs **1 worker** — the JSON flat file is not safe for concurrent
  writers. Use [redis-api](../redis-api/) or [csharp-api](../csharp-api/) if you
  want real multi-worker storage.

## VPS Configuration

**Socat bridge** — [`cgnat/vps/docker-compose.yml`](../../vps/docker-compose.yml)
```yaml
# Service name: socat-python-api
# Forwards VPS proxy network :5000 → WireGuard 10.8.0.2:5000
socat-python-api:
  image: alpine/socat:latest
  command: TCP4-LISTEN:5000,fork,reuseaddr TCP4:10.8.0.2:5000
  networks: [proxy]
```

**Traefik router + service** — [`cgnat/vps/traefik/dynamic.yml`](../../vps/traefik/dynamic.yml)
```yaml
routers:
  python-api:
    rule: "Host(`api.xore.rocks`)"
    entryPoints: [websecure]
    service: python-api
    tls:
      options: modern
    middlewares: [security-headers, rate-limit]

services:
  python-api:
    loadBalancer:
      servers:
        - url: "http://socat-python-api:5000"
      passHostHeader: true
```

**Cloudflare DNS:** A record → VPS IP, **Proxied 🟠**
