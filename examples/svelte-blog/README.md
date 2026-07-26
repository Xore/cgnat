# svelte-blog

Svelte 5 / SvelteKit blog example with Runes and server routes.  
Mirrors the `vui-blog` Express example, but using modern Svelte primitives.

Styled with the shared **xore** theme (`src/xore-theme.css`, a copy of
`template/xore-theme.css`). Every component uses theme classes and tokens —
no local `<style>` blocks override colors, fonts, radius, or backgrounds.

## Stack

| Layer | Tech |
|---|---|
| Frontend | Svelte 5 + SvelteKit (SSR + CSR) |
| Backend  | SvelteKit server routes + remote functions-ready API |
| Storage  | In-memory store (for demo), replace with real DB or JSON file if desired |
| Tunnel   | socat → VPS → Traefik → Cloudflare (same CGNAT pattern as `vui-blog`) |

## CGNAT pattern

The Svelte blog follows the same 4-step CGNAT pattern used by `vui-blog`:

```
1. Home: svelte-blog (:4174) + socat (bind=10.8.0.2:4174)
2. VPS:  socat bridge → 10.8.0.2:4174
3. VPS:  Traefik router + service in dynamic.yml
4. CF:   A record (orange cloud, proxied)
```

### 1. Home server (Dockge stack)

Place all files in a Dockge stack folder, e.g.:

```bash
/opt/stacks/svelte-blog/
```

Create `docker-compose.yml` in that folder:

```yaml
services:
  svelte-blog:
    image: node:22-alpine
    container_name: svelte-blog
    restart: unless-stopped
    working_dir: /app
    volumes:
      # Read-write: SvelteKit writes .svelte-kit/ during dev.
      - ./:/app
      # Named volume so rollup/esbuild native binaries build for alpine (musl),
      # never copied from the host.
      - svelte-node-modules:/app/node_modules
    # List form: a folded YAML scalar can inject a newline before && and break sh.
    command: ["sh", "-c", "npm install && npm run dev -- --host 0.0.0.0 --port 4174"]
    ports:
      - 127.0.0.1:4174:4174
    environment:
      # development, not production — vite/@sveltejs/kit are devDependencies.
      - NODE_ENV=development
      - TZ=Europe/Berlin
      - ADMIN_PASSWORD=change-me-svelte

  socat-svelte-blog:
    image: alpine/socat:latest
    container_name: socat-svelte-blog
    restart: unless-stopped
    command: TCP4-LISTEN:4174,bind=10.8.0.2,fork,reuseaddr TCP4:127.0.0.1:4174
    network_mode: host
    depends_on:
      - svelte-blog

volumes:
  svelte-node-modules:
```

> Deploying via Dockge: keep a **single** compose file per stack (Dockge prefers
> `compose.yaml` over `docker-compose.yml` and warns on duplicates), and use
> **Down → Up** after edits so named volumes are recreated. First boot runs
> `npm install`, which takes a minute or two.
>
> The dev server runs behind the tunnel, so Vite's host check must allow the
> public domain — `vite.config.ts` sets `server.allowedHosts: ['.xore.rocks']`.
> Change it to match your domain, otherwise Vite returns
> `Blocked request. This host is not allowed.`
>
> For a production deploy, prefer a build over the dev server (no host check,
> proper HMR-free serving):
> `command: ["sh", "-c", "npm install --include=dev && npm run build && node build/index.js"]`
> with `PORT=4174`, `HOST=0.0.0.0`, and `ORIGIN=https://your-domain` (adapter-node).

Then deploy:

```bash
cd /opt/stacks/svelte-blog
# stack folder contains docker-compose.yml and the svelte-blog project
sudo docker compose up -d
```

At this point:

- Home server runs SvelteKit dev server on `127.0.0.1:4174`
- socat binds `10.8.0.2:4174` and forwards to `127.0.0.1:4174`

### 2. VPS socat bridge

On the VPS, add a socat container that forwards the `proxy` network to the home
gateway over WireGuard (`10.8.0.2:4174`). Add to
[`cgnat/vps/docker-compose.yml`](../../vps/docker-compose.yml):

```yaml
  socat-svelte-blog:
    image: alpine/socat:latest
    container_name: socat-svelte-blog
    restart: unless-stopped
    command: TCP4-LISTEN:4174,fork,reuseaddr TCP4:10.8.0.2:4174
    networks: [proxy]
```

```bash
cd /root/vps && docker compose -f docker-compose.yml up -d
```

### 3. Traefik on VPS

Add a router + service to [`cgnat/vps/traefik/dynamic.yml`](../../vps/traefik/dynamic.yml)
(same style as the other services — Cloudflare Origin cert, shared middlewares,
upstream is the VPS socat container):

```yaml
http:
  routers:
    svelte-blog:
      rule: "Host(`svelte.xore.rocks`)"        # ← your domain
      entryPoints: [websecure]
      service: svelte-blog
      tls:
        options: modern
      middlewares: [security-headers, rate-limit]

  services:
    svelte-blog:
      loadBalancer:
        servers:
          - url: "http://socat-svelte-blog:4174"
        passHostHeader: true
```

Traefik terminates TLS from Cloudflare and forwards to `socat-svelte-blog`,
which bridges over WireGuard to the home server.

### 4. Cloudflare

Create a **proxied** A record pointing to the VPS:

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| A | `svelte` | `<VPS_PUBLIC_IP>` | 🟠 Proxied |

### 5. Verify end-to-end

```bash
curl http://127.0.0.1:4174            # home: SvelteKit dev server
curl http://10.8.0.2:4174             # from the VPS: through WireGuard
curl https://svelte.xore.rocks        # full path via Cloudflare
```

```
Browser → https://svelte.xore.rocks
  ▼ Cloudflare WAF + TLS
  ▼ VPS Traefik → socat-svelte-blog:4174
  ▼ WireGuard tunnel → 10.8.0.2:4174
  ▼ home socat → 127.0.0.1:4174 → SvelteKit
```

> Full walkthrough (WireGuard, Docker install, VPS hardening, Cloudflare):
> [`cgnat/docs/VPS-Guide.md`](../../docs/VPS-Guide.md).

## Features implemented

The Svelte blog uses several "new cool" Svelte 5 / SvelteKit features:

- **Runes API** (`$props`, `$state`) in the page and admin components
- **Server-side data loading** with `+page.server.ts` and `+layout.server.ts`
- **API routes** for public and admin JSON endpoints (`X-Admin-Token` guard)
- **Client admin flow** (login → table → create/edit/delete) in `src/routes/admin`
- Shared **xore theme** applied across layout, posts, single post, and admin
- TypeScript-first setup with strict mode

You can extend this with SvelteKit remote functions and a real persistence layer (file-based or DB) once you decide how you want to back the blog.

## File structure

```text
svelte-blog/
├── README.md
├── docker-compose.yml
├── package.json
├── vite.config.ts
├── svelte.config.js         # adapter-node + $lib alias
├── tsconfig.json
└── src/
    ├── app.html             # SvelteKit shell
    ├── app.css              # theme entry (imports ./xore-theme.css)
    ├── xore-theme.css       # copy of ../../../template/xore-theme.css
    ├── lib/
    │   ├── types.ts         # Post type
    │   ├── store.ts         # In-memory post store (seeded)
    │   └── api.ts           # client fetch helper + admin-token store
    └── routes/
        ├── +layout.svelte           # scene, header/nav, marquee, footer (theme)
        ├── +layout.server.ts
        ├── +layout.ts
        ├── +page.server.ts
        ├── +page.svelte             # posts list (post-grid / post-card)
        ├── post/[id]/+page.server.ts
        ├── post/[id]/+page.svelte   # single post (post-single)
        ├── admin/+page.svelte       # gate + table + create/edit form
        ├── api/posts/+server.ts     # public posts API
        ├── api/admin/login/+server.ts   # admin login
        └── api/admin/posts/+server.ts   # admin CRUD API
```
