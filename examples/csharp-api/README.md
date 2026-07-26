# Example: ASP.NET Core 9 + PostgreSQL Blog (C#)

The **xore//blog** system on a C# backend with a real database — the most
advanced blog example in this folder. Same frontend and REST API contract as
every other blog example; this one stores posts in PostgreSQL via EF Core.

| Layer | Tech |
|---|---|
| Frontend | Shared xore//blog SPA (`wwwroot/` — vanilla JS, hash routing) |
| Backend | ASP.NET Core 9 minimal API (single `Program.cs`) |
| Storage | PostgreSQL 17 via EF Core (`Npgsql.EntityFrameworkCore.PostgreSQL`) |
| Admin auth | `X-Admin-Token` header, password from `ADMIN_PASSWORD` env |

Extras on top of the shared contract:

- **Built-in rate limiting** — per-client-IP fixed window (100 req / 10 s)
- **Liveness + readiness probes** — `/health` and `/health/ready` (pings Postgres, 503 if down)
- **Multi-stage Dockerfile** — SDK compiles, slim `aspnet:9.0-alpine` serves, non-root
- **Ordered startup** — socat waits for the API healthcheck, the API waits for `pg_isready`
- Schema auto-created on startup with retry while Postgres warms up

## Files to place in the Dockge stack folder

```
/opt/stacks/csharp-api/
├── docker-compose.yml   ← home server stack (postgres + api + socat)
├── Dockerfile           ← multi-stage build
├── .dockerignore
├── BlogApi.csproj       ← project file (one NuGet package)
├── Program.cs           ← the whole API
└── wwwroot/             ← shared frontend (index.html, app.js, xore.css)
```

## Quick Start (Home Server)

```bash
docker compose up -d --build
curl http://127.0.0.1:5002/health
curl http://127.0.0.1:5002/health/ready
curl http://127.0.0.1:5002/api/posts
# then open http://127.0.0.1:5002 — admin panel under ADMIN (nav)
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
| GET | /health | public | Liveness (post count, uptime) |
| GET | /health/ready | public | Readiness — pings Postgres, 503 if unreachable |

## Notes

- Change the Postgres password (both `POSTGRES_PASSWORD` occurrences) **and**
  the admin password (`ADMIN_PASSWORD=change-me-cs`) in `docker-compose.yml`.
- Postgres is not exposed to the host — only reachable inside the Docker network.
- Named volume `pg-data` persists posts across restarts.
- After code changes: `docker compose up -d --build`.

## VPS Configuration

**Socat bridge** — [`cgnat/vps/docker-compose.yml`](../../vps/docker-compose.yml)
```yaml
# Service name: socat-csharp-api
# Forwards VPS proxy network :5002 → WireGuard 10.8.0.2:5002
socat-csharp-api:
  image: alpine/socat:latest
  command: TCP4-LISTEN:5002,fork,reuseaddr TCP4:10.8.0.2:5002
  networks: [proxy]
```

**Traefik router + service** — [`cgnat/vps/traefik/dynamic.yml`](../../vps/traefik/dynamic.yml)
```yaml
routers:
  csharp-api:
    rule: "Host(`csharp.xore.rocks`)"
    entryPoints: [websecure]
    service: csharp-api
    tls:
      options: modern
    middlewares: [security-headers, rate-limit-api]

services:
  csharp-api:
    loadBalancer:
      servers:
        - url: "http://socat-csharp-api:5002"
      passHostHeader: true
```

**Cloudflare DNS:** A record → VPS IP, **Proxied 🟠**
