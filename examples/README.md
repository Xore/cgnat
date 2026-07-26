# Examples

Examples for exposing services through the CGNAT VPS gateway. Application
folders generally contain a home-side `docker-compose.yml` and a `README.md`;
the honeypot is a split deployment. SSO/forward-auth is not one of these
examples — it's an optional add-on repo, [Xore/auth-backend](https://github.com/Xore/auth-backend).

## One blog, many backends

Every app example is the same **xore//blog** system — identical frontend
(xore theme), identical REST API contract (`/api/posts` public, admin CRUD via
the `X-Admin-Token` header, `/health`) — implemented in a different language
with a different storage story. Pick the stack you want to learn; the blog
behaves the same everywhere.

| Example | Port | Backend | Storage |
|---------|------|---------|---------|
| [static-site](./static-site/) | 8080 | none — nginx, read-only mode | `posts.json` edited by hand |
| [python-api](./python-api/) | 5000 | Flask + Gunicorn | JSON flat file (volume) |
| [node-express-api](./node-express-api/) | 3000 | Node.js + Express | JSON flat file (volume) |
| [redis-api](./redis-api/) | 5001 | Flask + Gunicorn | Redis (sorted-set index) |
| [csharp-api](./csharp-api/) | 5002 | ASP.NET Core 9 minimal API | PostgreSQL via EF Core |
| [go-api](./go-api/) | 5003 | Go stdlib, ~10 MB scratch image | JSON file, frontend embedded (`go:embed`) |
| [rust-api](./rust-api/) | 5004 | Rust + Axum, static musl binary | JSON file, frontend embedded (`include_str!`) |
| [vui-blog](./vui-blog/) | 3000 | Express serving a Vue 3 SPA | JSON flat file (volume) |
| [vui-blog-auth](./vui-blog-auth/) | 3000 | vui-blog **+ login-wall gateway** container in front | JSON flat file (volume) |
| [svelte-blog](./svelte-blog/) | 4174 | SvelteKit 5 server routes | JSON flat file (volume) |

> vui-blog, vui-blog-auth and node-express-api all use port 3000 — run only one.

## Auth & security examples

| Example | Port | Description |
|---------|------|-------------|
| [Xore/auth-backend](https://github.com/Xore/auth-backend) (separate repo) | 4181 | **Hardened Traefik forward-auth SSO** (`auth.<domain>`) — one login protects any service; lockout, 2FA, bot traps |
| [vui-blog-auth](./vui-blog-auth/) | 3000 | Auth-gateway container (Go reverse proxy, HMAC sessions) gating the blog; VPS-side auth options documented |
| [honeypot-stack](https://github.com/Xore/honeypot-stack) | 30+ TCP/UDP surfaces | Separate public repository: home Dockge stack + VPS Portbridge/Suricata, Cowrie, multipot, Dionaea, S7/OT Conpot personas, HTTP/API, SNARE/TANNER, dashboard, payload/script analysis, ELK, EveBox and Arkime |

## Infrastructure examples (not blogs)

| Example | Port | Description |
|---------|------|-------------|
| [reverse-proxy](./reverse-proxy/) | any | Forward traffic to any upstream (no app container needed) |
| [uptime-kuma](./uptime-kuma/) | 3001 | Self-hosted uptime monitoring dashboard |
| [filebrowser](./filebrowser/) | 8070 | Web-based file manager |

## Usage Pattern

Every example follows the same 4-step pattern:

```
1. Home: app container + socat (bind=10.8.0.2)
2. VPS:  socat bridge (proxy network)
3. VPS:  Traefik router + service in dynamic.yml
4. CF:   A record (orange cloud, proxied)
```

See the [full guide](../docs/VPS-Guide.md) for the complete setup.

> The honeypot stack is the exception to the simple HTTP pattern: raw TCP/UDP
> reaches VPS Portbridge and crosses WireGuard; authenticated web investigation
> routes use Traefik. Suricata captures on the VPS before forwarding.
