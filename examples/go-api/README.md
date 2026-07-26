# Example: Go Blog (stdlib, scratch image)

The **xore//blog** system on a Go backend using **only the standard library** —
no frameworks, no dependencies. The frontend is embedded into the binary with
`go:embed`, so the whole blog ships as one static binary in a `scratch` image
(~10 MB total).

| Layer | Tech |
|---|---|
| Frontend | Shared xore//blog SPA, embedded via `go:embed` (`static/`) |
| Backend | Go stdlib `net/http` with 1.22+ pattern routing |
| Storage | JSON file in a named volume (`/data/posts.json`, atomic replace) |
| Admin auth | `X-Admin-Token` header, password from `ADMIN_PASSWORD` env |

Extras on top of the shared contract:

- **Structured JSON logging** (`log/slog`) with request-logging + panic-recovery middleware
- **Graceful shutdown** — drains in-flight requests on SIGTERM
- **Self-healthcheck** — `/server -healthcheck` probes its own `/health`, so the
  scratch image needs no shell, wget or curl
- Runs as non-root (`USER 65534`); `/data` ownership is baked into the image so
  the named volume inherits it

## Files to place in the Dockge stack folder

```
/opt/stacks/go-api/
├── docker-compose.yml   ← home server stack
├── Dockerfile           ← multi-stage build (golang → scratch)
├── .dockerignore
├── go.mod
├── main.go              ← the whole API
└── static/              ← shared frontend (embedded at build time)
```

## Quick Start (Home Server)

```bash
docker compose up -d --build
curl http://127.0.0.1:5003/health
curl http://127.0.0.1:5003/api/posts
# then open http://127.0.0.1:5003 — admin panel under ADMIN (nav)
```

Set the admin password in `docker-compose.yml` (`ADMIN_PASSWORD=change-me-go`).

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

- Posts persist in the `blog-data` named volume (`/data/posts.json`).
- Frontend changes require a rebuild (`docker compose up -d --build`) — the
  files are compiled into the binary.

## VPS Configuration

**Socat bridge** — [`cgnat/vps/docker-compose.yml`](../../vps/docker-compose.yml)
```yaml
# Service name: socat-go-api
# Forwards VPS proxy network :5003 → WireGuard 10.8.0.2:5003
socat-go-api:
  image: alpine/socat:latest
  command: TCP4-LISTEN:5003,fork,reuseaddr TCP4:10.8.0.2:5003
  networks: [proxy]
```

**Traefik router + service** — [`cgnat/vps/traefik/dynamic.yml`](../../vps/traefik/dynamic.yml)
```yaml
routers:
  go-api:
    rule: "Host(`go.xore.rocks`)"
    entryPoints: [websecure]
    service: go-api
    tls:
      options: modern
    middlewares: [security-headers, rate-limit-api]

services:
  go-api:
    loadBalancer:
      servers:
        - url: "http://socat-go-api:5003"
      passHostHeader: true
```

**Cloudflare DNS:** A record → VPS IP, **Proxied 🟠**
