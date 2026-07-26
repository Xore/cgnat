# Example: Static Blog (nginx, no backend)

The **xore//blog** system with **no backend at all**: nginx serves the shared
frontend in read-only mode, and posts live in a plain `posts.json` file.
Publishing a post means editing a text file — the whole CMS is `posts.json`.

Every other example in this folder serves the exact same blog with a real
backend (Flask, Express, Redis, ASP.NET Core + Postgres, Go, Rust). This one
shows the floor of the pattern: same look, same routes, zero moving parts.

| Layer | Tech |
|---|---|
| Frontend | Shared xore//blog SPA in read-only mode (`readOnly: true`) |
| Backend | none — nginx only |
| Storage | `html/posts.json`, edited by hand |
| Admin | none (the ADMIN nav is hidden in read-only mode) |

The old CGNAT documentation mini-site is still served under `/docs/`.

## Files

```
static-site/
├── docker-compose.yml   ← home server stack (Dockge)
├── nginx.conf           ← optimised Nginx config
└── html/
    ├── index.html         ← blog entry (readOnly config)
    ├── app.js             ← shared frontend
    ├── xore.css           ← shared xore theme
    ├── posts.json         ← ← your posts live here
    ├── shared.css / .js   ← used by the docs pages
    └── docs/              ← CGNAT documentation pages (/docs/)
```

## Quick Start (Home Server)

```bash
docker compose up -d
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8080/posts.json
# then open http://127.0.0.1:8080
```

## Publishing a post

Append an object to `html/posts.json`:

```json
{
  "id": "my-post",
  "title": "My new post",
  "slug": "my-new-post",
  "content": "Plain text.\n\nBlank lines become paragraphs.",
  "published": true,
  "createdAt": 1752864000000,
  "updatedAt": 1752864000000
}
```

- `createdAt`/`updatedAt` are Unix epoch **milliseconds** (`date +%s000`).
- `"published": false` hides a post — same drafts behavior as the backend examples.
- No restart needed; reload the page.

## VPS Configuration

**Socat bridge** — [`cgnat/vps/docker-compose.yml`](../../vps/docker-compose.yml)
```yaml
# Service name: socat-static
# Forwards VPS proxy network :8080 → WireGuard 10.8.0.2:8080
socat-static:
  image: alpine/socat:latest
  command: TCP4-LISTEN:8080,fork,reuseaddr TCP4:10.8.0.2:8080
  networks: [proxy]
```

**Traefik router + service** — [`cgnat/vps/traefik/dynamic.yml`](../../vps/traefik/dynamic.yml)
```yaml
routers:
  static-site:
    rule: "Host(`static.xore.rocks`)"
    entryPoints: [websecure]
    service: static-site
    tls:
      options: modern
    middlewares: [security-headers, rate-limit]

services:
  static-site:
    loadBalancer:
      servers:
        - url: "http://socat-static:8080"
      passHostHeader: true
```

**Cloudflare DNS:** A record → VPS IP, **Proxied 🟠**
