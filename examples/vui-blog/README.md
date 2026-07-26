# vui-blog

Vue 3 blog (posts + admin CRUD) on a Node.js/Express backend, styled with the
shared **xore** theme. Follows the standard CGNAT 4-step pattern.

Express (`app.js`) serves the built Vue SPA from `dist/` **and** the REST API on
port 3000 — one origin, one container.

## Stack

| Layer | Tech |
|---|---|
| Frontend | Vue 3 + vue-router SPA (Vite build) |
| Backend | Node.js + Express 4 REST API |
| Storage | JSON flat file (`data/posts.json`) |
| Theme | Shared xore theme (`src/assets/xore-theme.css`) |
| Tunnel | socat → VPS → Traefik → Cloudflare |

## Project layout

```text
vui-blog/
├── app.js               Express: REST API + serves dist/
├── index.html           Vite entry
├── vite.config.mjs      Vite + Vue plugin, /api dev proxy
├── package.json         express + vue + vite (build => dist/)
├── docker-compose.yml   build the SPA, run Express, socat sidecar
└── src/
    ├── main.js          Vue app + router + theme import
    ├── App.vue          scene, header/nav, marquee, footer (xore theme)
    ├── assets/          xore-theme.css (copied) + import entry
    ├── lib/api.js       fetch helper + admin-token ref
    ├── router/          routes: /, /post/:id, /admin, /admin/new, /admin/:id
    └── views/           PostsView, PostView, AdminView, AdminFormView
```

## Features

- Posts list, single post, and admin (login → table → create / edit / delete)
- Admin token auth via the `X-Admin-Token` header
- Slug auto-generated from the title (locks on manual edit)
- Ambient scene, sticky header/nav, marquee ticker, dark cards, admin table —
  all from the shared xore theme; no local styles override theme tokens

## Develop locally

```bash
# terminal 1 — API
node app.js                 # http://localhost:3000

# terminal 2 — Vite dev server (proxies /api to :3000)
npm install
npm run dev                 # http://localhost:5173
```

Production build (what the container runs): `npm run build && node app.js` —
Express then serves `dist/` + the API on :3000.

## Setup (Docker)

```bash
# 1. Place files in a Dockge stack folder (a single compose file per stack)
#    /opt/stacks/vui-blog/

# 2. Set the admin password in docker-compose.yml
#    environment: ADMIN_PASSWORD=your-secret-here

# 3. Deploy (Down -> Up in Dockge after edits so volumes recreate)
docker compose up -d   # npm install --include=dev && npm run build && node app.js
```

## CGNAT pattern

```
1. Home: vui-blog (:3000) + socat (bind=10.8.0.2:3000)
2. VPS:  socat bridge → 10.8.0.2:3000
3. VPS:  Traefik router + service in dynamic.yml
4. CF:   A record (orange cloud, proxied)
```

### 1. Home server (Dockge stack)

Put this example's files in a Dockge stack folder (one compose file per stack):

```bash
/opt/stacks/vui-blog/
```

Use the [`docker-compose.yml`](./docker-compose.yml) in this folder as-is — it builds
the Vue SPA and runs Express (`app.js`) serving `dist/` + the API on
`127.0.0.1:3000`, plus a socat sidecar that binds the WireGuard interface:

```yaml
  socat-vui-blog:
    image: alpine/socat:latest
    container_name: socat-vui-blog
    restart: unless-stopped
    command: TCP4-LISTEN:3000,bind=10.8.0.2,fork,reuseaddr TCP4:127.0.0.1:3000
    network_mode: host
    depends_on:
      - vui-blog
```

```bash
cd /opt/stacks/vui-blog && docker compose up -d
```

At this point the app serves on `127.0.0.1:3000` and socat exposes it on
`10.8.0.2:3000` (WireGuard only, not the LAN).

### 2. VPS socat bridge

On the VPS, add a socat container that forwards the `proxy` network to the home
gateway over WireGuard. Add to
[`cgnat/vps/docker-compose.yml`](../../vps/docker-compose.yml):

```yaml
  socat-vui-blog:
    image: alpine/socat:latest
    container_name: socat-vui-blog
    restart: unless-stopped
    command: TCP4-LISTEN:3000,fork,reuseaddr TCP4:10.8.0.2:3000
    networks: [proxy]
```

```bash
cd /root/vps && docker compose -f docker-compose.yml up -d
```

### 3. Traefik on VPS

Add a router + service to [`cgnat/vps/traefik/dynamic.yml`](../../vps/traefik/dynamic.yml)
(Cloudflare Origin cert, shared middlewares, upstream is the VPS socat container):

```yaml
http:
  routers:
    vui-blog:
      rule: "Host(`vui.xore.rocks`)"          # ← your domain
      entryPoints: [websecure]
      service: vui-blog
      tls:
        options: modern
      middlewares: [security-headers, rate-limit]

  services:
    vui-blog:
      loadBalancer:
        servers:
          - url: "http://socat-vui-blog:3000"
        passHostHeader: true
```

### 4. Cloudflare

Create a **proxied** A record pointing to the VPS:

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| A | `vui` | `<VPS_PUBLIC_IP>` | 🟠 Proxied |

### 5. Verify end-to-end

```bash
curl http://127.0.0.1:3000/health     # home: Express app
curl http://10.8.0.2:3000/health      # from the VPS: through WireGuard
curl https://vui.xore.rocks/health    # full path via Cloudflare
```

```
Browser → https://vui.xore.rocks
  ▼ Cloudflare WAF + TLS
  ▼ VPS Traefik → socat-vui-blog:3000
  ▼ WireGuard tunnel → 10.8.0.2:3000
  ▼ home socat → 127.0.0.1:3000 → Express
```

> Full walkthrough (WireGuard, Docker install, VPS hardening, Cloudflare):
> [`cgnat/docs/VPS-Guide.md`](../../docs/VPS-Guide.md).

## API

| Method | Path | Auth | Description |
|--------|------|------|-------------|
| GET | /api/posts | public | List published posts |
| GET | /api/posts/:id | public | Get single post |
| GET | /api/admin/posts | admin | List all posts |
| POST | /api/admin/posts | admin | Create post |
| PUT | /api/admin/posts/:id | admin | Update post |
| DELETE | /api/admin/posts/:id | admin | Delete post |
| GET | /health | public | Health check |
