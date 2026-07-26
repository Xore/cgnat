# Example: Express Blog (Node.js, Dockge / no Dockerfile)

The **xore//blog** system on a Node.js + Express backend. Same frontend and REST
API contract as every blog example in this folder — this one is the closest
sibling of [vui-blog](../vui-blog/), but with the framework-free frontend
instead of Vue.

| Layer | Tech |
|---|---|
| Frontend | Shared xore//blog SPA (`public/` — vanilla JS, hash routing) |
| Backend | Node.js 22 + Express 4 |
| Storage | JSON flat file in a named volume (`/app/data/posts.json`) |
| Admin auth | `X-Admin-Token` header, password from `ADMIN_PASSWORD` env |

## Files to place in the Dockge stack folder

```
/opt/stacks/node-express-api/
├── docker-compose.yml   ← home server stack
├── app.js               ← Express app (API + serves public/)
└── public/              ← shared frontend (index.html, app.js, xore.css)
```

## Quick Start (Home Server)

```bash
docker compose up -d
curl http://127.0.0.1:3000/health
curl http://127.0.0.1:3000/api/posts
# then open http://127.0.0.1:3000 — admin panel under ADMIN (nav)
```

Set the admin password in `docker-compose.yml` (`ADMIN_PASSWORD=change-me-js`).

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
- Port 3000 is shared with [vui-blog](../vui-blog/) — run only one of the two
  on the home server.

## VPS Configuration

**Socat bridge** — [`cgnat/vps/docker-compose.yml`](../../vps/docker-compose.yml)
```yaml
# Service name: socat-node-api
# Forwards VPS proxy network :3000 → WireGuard 10.8.0.2:3000
socat-node-api:
  image: alpine/socat:latest
  command: TCP4-LISTEN:3000,fork,reuseaddr TCP4:10.8.0.2:3000
  networks: [proxy]
```

**Traefik router + service** — [`cgnat/vps/traefik/dynamic.yml`](../../vps/traefik/dynamic.yml)
```yaml
routers:
  node-api:
    rule: "Host(`node.xore.rocks`)"
    entryPoints: [websecure]
    service: node-api
    tls:
      options: modern
    middlewares: [security-headers, rate-limit]

services:
  node-api:
    loadBalancer:
      servers:
        - url: "http://socat-node-api:3000"
      passHostHeader: true
```

**Cloudflare DNS:** A record → VPS IP, **Proxied 🟠**
