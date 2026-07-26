# Example: Rust Axum Blog

The **xore//blog** system on a Rust backend built with **Axum 0.8** + Tokio.
The frontend is embedded into the binary with `include_str!`, compiled to a
static musl binary and shipped in a small Alpine image.

| Layer | Tech |
|---|---|
| Frontend | Shared xore//blog SPA, embedded via `include_str!` (`static/`) |
| Backend | Rust + Axum 0.8 (typed extractors, shared `RwLock` state) |
| Storage | JSON file in a named volume (`/data/posts.json`, atomic save) |
| Admin auth | `X-Admin-Token` header, password from `ADMIN_PASSWORD` env |

Extras on top of the shared contract:

- **Graceful shutdown** — drains in-flight requests on SIGTERM
- **Dependency-caching Dockerfile** — axum/tokio compile against a dummy
  `main.rs`, so code-only rebuilds are fast
- Runs as non-root, `strip` + `lto` release profile for a small binary

## Files to place in the Dockge stack folder

```
/opt/stacks/rust-api/
├── docker-compose.yml   ← home server stack
├── Dockerfile           ← multi-stage build (rust → alpine)
├── .dockerignore
├── Cargo.toml
├── src/
│   └── main.rs          ← the whole API
└── static/              ← shared frontend (embedded at build time)
```

## Quick Start (Home Server)

```bash
docker compose up -d --build   # first build takes a few minutes
curl http://127.0.0.1:5004/health
curl http://127.0.0.1:5004/api/posts
# then open http://127.0.0.1:5004 — admin panel under ADMIN (nav)
```

Set the admin password in `docker-compose.yml` (`ADMIN_PASSWORD=change-me-rs`).

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
  files are compiled into the binary. Rebuilds are fast thanks to the
  dependency-caching layer.

## VPS Configuration

**Socat bridge** — [`cgnat/vps/docker-compose.yml`](../../vps/docker-compose.yml)
```yaml
# Service name: socat-rust-api
# Forwards VPS proxy network :5004 → WireGuard 10.8.0.2:5004
socat-rust-api:
  image: alpine/socat:latest
  command: TCP4-LISTEN:5004,fork,reuseaddr TCP4:10.8.0.2:5004
  networks: [proxy]
```

**Traefik router + service** — [`cgnat/vps/traefik/dynamic.yml`](../../vps/traefik/dynamic.yml)
```yaml
routers:
  rust-api:
    rule: "Host(`rust.xore.rocks`)"
    entryPoints: [websecure]
    service: rust-api
    tls:
      options: modern
    middlewares: [security-headers, rate-limit-api]

services:
  rust-api:
    loadBalancer:
      servers:
        - url: "http://socat-rust-api:5004"
      passHostHeader: true
```

**Cloudflare DNS:** A record → VPS IP, **Proxied 🟠**
