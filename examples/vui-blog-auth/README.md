# vui-blog-auth

The [vui-blog](../vui-blog/) example with a **login wall in front of it**. A
second container — the `auth-gateway` — sits between socat and the blog and
serves a login page; nothing reaches the blog until the visitor holds a valid
session cookie.

```
socat (10.8.0.2:3000) → auth-gateway (:8080) → vui-blog (:3000, internal only)
                             │
                    login page + HMAC session cookie
```

## Why two containers?

The blog container is **not published to the host** at all (`expose: 3000`, no
`ports:`). The only thing bound to `127.0.0.1:3000` — and therefore the only
thing socat forwards over WireGuard — is the auth-gateway. So the blog is
physically unreachable without passing the gate.

### Two independent auth layers

| Layer | Guards | Mechanism |
|---|---|---|
| **auth-gateway** | the whole site (reading *and* writing) | login form → HMAC-signed cookie |
| **blog admin** | editing posts | the blog's own `X-Admin-Token` (unchanged from vui-blog) |

A visitor first logs into the gate to see anything, then logs into the blog
admin panel to create/edit posts. Defense in depth — and either password can be
rotated independently.

## The auth-gateway

A small dependency-free Go reverse proxy (stdlib only), compiled to a static
binary in a `scratch` image (~7 MB). Features:

- **Stateless sessions** — the cookie is `expiry|HMAC-SHA256(expiry)`, verified
  in constant time. No session store, so it scales horizontally and survives
  restarts as long as `COOKIE_SECRET` is stable.
- **Brute-force throttle** — 5 failed logins per IP, then a 5-minute lockout.
- **Constant-time credential compare**, `HttpOnly` + `SameSite=Lax` + `Secure`
  cookies, open-redirect-safe `next` handling.
- **Self-healthcheck** — `/_auth/health` (unauthenticated) for Docker/Traefik.

### Configuration (env vars)

| Var | Default | Notes |
|---|---|---|
| `UPSTREAM` | `http://vui-blog:3000` | where to proxy authenticated traffic |
| `AUTH_USERNAME` | `admin` | gate username |
| `AUTH_PASSWORD` | `change-me-gate` | **change this** |
| `COOKIE_SECRET` | *(random)* | **set this** — `openssl rand -hex 32`. If unset, a random key is generated and sessions drop on restart |
| `SESSION_TTL_HOURS` | `12` | how long a login lasts |
| `COOKIE_SECURE` | `true` | set `false` only for plain-HTTP local testing |
| `LISTEN_ADDR` | `:8080` | gateway listen address |

Routes the gateway owns (everything else is proxied):
`/_auth/login`, `/_auth/logout`, `/_auth/health`.

## Setup (Docker)

```bash
# 1. Place this whole folder (including auth-gateway/) in a Dockge stack dir:
#    /opt/stacks/vui-blog-auth/

# 2. Edit docker-compose.yml:
#    - auth-gateway: AUTH_PASSWORD + COOKIE_SECRET (openssl rand -hex 32)
#    - vui-blog:     ADMIN_PASSWORD

# 3. Deploy (builds the gateway image, then npm install + vite build)
docker compose up -d --build
```

Then browse to `http://127.0.0.1:3000` → you get the **gate**. Log in with
`AUTH_USERNAME` / `AUTH_PASSWORD` → the blog appears. The blog's own `ADMIN`
panel still needs `ADMIN_PASSWORD`.

```bash
# health checks
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/_auth/health   # 200
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/               # 303 → /_auth/login
```

## CGNAT pattern

Same as vui-blog — **still port 3000**, so the VPS socat bridge and Traefik
router are unchanged. Point Cloudflare at a new subdomain (e.g. `blog-auth`):

```
1. Home: auth-gateway (:3000) → vui-blog (internal) + socat (bind=10.8.0.2:3000)
2. VPS:  socat bridge → 10.8.0.2:3000
3. VPS:  Traefik router + service in dynamic.yml
4. CF:   A record (orange cloud, proxied)
```

**VPS socat bridge** — [`cgnat/vps/docker-compose.yml`](../../vps/docker-compose.yml)
```yaml
socat-vui-blog-auth:
  image: alpine/socat:latest
  command: TCP4-LISTEN:3000,fork,reuseaddr TCP4:10.8.0.2:3000
  networks: [proxy]
```

> Home port 3000 is shared with vui-blog and node-express-api — run only one of
> the three on the home server.

**Traefik router + service** — [`cgnat/vps/traefik/dynamic.yml`](../../vps/traefik/dynamic.yml)
```yaml
routers:
  vui-blog-auth:
    rule: "Host(`blog-auth.xore.rocks`)"
    entryPoints: [websecure]
    service: vui-blog-auth
    tls:
      options: modern
    middlewares: [security-headers, rate-limit]

services:
  vui-blog-auth:
    loadBalancer:
      servers:
        - url: "http://socat-vui-blog-auth:3000"
      passHostHeader: true
```

**Cloudflare DNS:** A record → VPS IP, **Proxied 🟠**

## Doing the authentication on the VPS side instead

You can move the login wall to the VPS so the home server just runs the plain
blog. Two options, from simplest to richest:

### Option A — Traefik BasicAuth (one middleware, no extra container)

The quickest VPS-side gate. Add a middleware and attach it to the router in
[`dynamic.yml`](../../vps/traefik/dynamic.yml):

```yaml
http:
  middlewares:
    blog-auth:
      basicAuth:
        users:
          # htpasswd -nB admin   → paste the bcrypt hash, double the $ signs
          - "admin:$$2y$$05$$b8...hash...here"

  routers:
    vui-blog:
      rule: "Host(`vui.xore.rocks`)"
      entryPoints: [websecure]
      service: vui-blog
      tls: { options: modern }
      middlewares: [security-headers, rate-limit, blog-auth]   # ← added
```

Here the home server can run the **unmodified [vui-blog](../vui-blog/)** — no
gateway needed. Downside: a browser Basic-auth popup, not a styled login page.

### Option B — run the auth-gateway on the VPS (styled login, sessions)

Build the same gateway on the VPS and put it in the `proxy` network, pointing
`UPSTREAM` at the existing socat bridge. Traefik routes to the gateway instead
of straight to socat:

```yaml
# cgnat/vps/docker-compose.yml
  auth-gateway:
    build: ../examples/vui-blog-auth/auth-gateway   # or a prebuilt image
    container_name: auth-gateway
    restart: unless-stopped
    environment:
      - UPSTREAM=http://socat-vui-blog:3000   # the existing bridge to the home blog
      - AUTH_PASSWORD=change-me-gate
      - COOKIE_SECRET=<openssl rand -hex 32>
    networks: [proxy]
```
```yaml
# dynamic.yml — point the service at the gateway
services:
  vui-blog:
    loadBalancer:
      servers:
        - url: "http://auth-gateway:8080"     # was http://socat-vui-blog:3000
      passHostHeader: true
```

Now auth happens entirely on the VPS; the home server runs the plain blog and
never sees an unauthenticated request beyond the tunnel. The gateway is
placement-agnostic — the only thing that changes between "home side" and "VPS
side" is where it runs and what `UPSTREAM` points at.

## API

Unchanged from [vui-blog](../vui-blog/) — see its README for the full endpoint
table. The gateway is transparent once you're authenticated.
