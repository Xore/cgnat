# Complete Stack Setup — step by step

A practical, ordered checklist to bring up the **whole** system: the VPS gateway,
every example app, and the honeypot. SSO (the auth portal) is an optional
add-on covered separately — see Part B. It assumes the base
infrastructure from **[VPS-Guide.md](VPS-Guide.md)** is done:

- ✅ Docker on both the VPS and the home server
- ✅ WireGuard tunnel up (VPS `10.8.0.1` ↔ home `10.8.0.2`)
- ✅ Cloudflare **Origin certificate** on the VPS at `vps/traefik/certs/`
- ✅ A domain on Cloudflare (this guide uses `xore.rocks` — replace throughout)
- ✅ The home server runs stacks with **Dockge** under `/opt/stacks/`
- ✅ The VPS runs plain Docker Compose from `/root/vps/docker-compose.yml`

Everything lives in the repo: the VPS side in [`cgnat/vps/`](../vps/), the apps in
[`cgnat/examples/`](../examples/). Home apps bind the WireGuard IP `10.8.0.2`; the
VPS forwards each to the internet (HTTP via Traefik, raw via socat/portbridge).

---

## Part A — VPS gateway (Traefik)

1. Copy `cgnat/vps/` to `/root/vps/` on the VPS
   (include `traefik/`, `traefik/certs/`, and `portbridge/`).
2. Edit `traefik/dynamic.yml` — replace every `xore.rocks` with your domain.
3. Deploy:
   ```bash
   cd /root/vps && docker compose -f docker-compose.yml up -d
   docker compose logs -f traefik      # should be clean
   ```

The `dynamic.yml` is watched live — editing it re-loads routes with no restart.
All the socat bridges (including the honeypot's `socat-hp-*` and `portbridge`)
are already in this stack; they just forward to `10.8.0.2` and sit idle until the
matching home stack is up.

---

## Part B — Auth portal (login for every dashboard) — optional add-on

SSO is **not part of this repo**. It lives in its own repository,
[Xore/auth-backend](https://github.com/Xore/auth-backend), so this repo stays a
standalone tunnel/reverse-proxy setup with no auth coupling.

1. Clone it and deploy with its own install files (`docker-compose.yml` +
   `.env.example` — set `COOKIE_SECRET`, `AUTH_PASSWORD`, etc. there):
   ```bash
   git clone https://github.com/Xore/auth-backend
   cd auth-backend && cp .env.example .env   # edit values
   docker compose up -d --build auth-portal
   ```
   Its `auth-portal` container joins this stack's `proxy` network.
2. Add the `auth-portal` router + service to
   [`vps/traefik/dynamic.yml`](../vps/traefik/dynamic.yml) — the snippet is in
   [`vps/README.md`](../vps/README.md). The `forward-auth` middleware is
   already defined and attached to the honeypot UI routers; it is fail-closed
   (5xx) until `auth-portal` is running. Any router using `forward-auth` then
   needs a login.

For account deletion, password/TOTP/passkey recovery, or a complete
administrator reset, see auth-backend's own credential-recovery doc.

---

## Part C — Cloudflare DNS

Add **proxied (🟠) A records** → your VPS public IP for every hostname you use.
Grey-cloud (DNS-only) only for raw game/TCP ports.

| Subdomain | Points at | Cloud |
|---|---|---|
| `@`, `www` | homepage ([Xore/www](https://github.com/Xore/www), optional) | 🟠 |
| `auth` | auth portal ([Xore/auth-backend](https://github.com/Xore/auth-backend), optional) | 🟠 |
| `status`, `ha` (or whatever you pick) | your example apps and upstreams | 🟠 |
| `decoy`, `www-portal` | HTTP honeypots | 🟠 |
| `honeypot`/`dashboard`, `kibana`, `tanner`, `evebox`, `arkime` | honeypot investigation UIs (behind auth) | 🟠 |
| `minecraft` (if used) | game server | ⚪ grey |

In Cloudflare **SSL/TLS → Overview**, set mode to **Full (strict)** so the Origin
cert is validated.

---

## Part D — Example app stacks (home server)

Each example is a home Dockge stack that binds `10.8.0.2`; its VPS socat bridge
and Traefik route already exist in Part A. So per example it's just: deploy the
home stack, then confirm the subdomain.

Pick the ones you want (see [examples/README.md](../examples/README.md)). For any example:

```bash
# on the HOME server
mkdir -p /opt/stacks/<example> && cd /opt/stacks/<example>
# copy that example's files here (compose + app/build folders), then:
docker compose up -d --build
curl -s http://10.8.0.2:<port>/            # local check over WireGuard
```

Then browse `https://<subdomain>.xore.rocks`. Reference ports/subdomains:

| Example | Home port | Subdomain |
|---|---|---|
| reverse-proxy | any | your choice |
| uptime-kuma | 3001 | status |

---

## Part E — Honeypot (home server + the VPS tunnels)

> ⚠ **First** move real admin SSH off port 22 (`scripts/harden-vps.sh` → 2222)
> and confirm you can log in on 2222 — the honeypot claims port 22.

1. **Home:** clone the separate public
   [`Xore/honeypot-stack`](https://github.com/Xore/honeypot-stack) repository
   to `/opt/stacks/honeypot-stack/`. Its source file is named
   `docker-compose.yml`; Dockge's authoritative deployed filename is
   `compose.yml`, so copy it while deploying:
   ```bash
   cd /opt/stacks/honeypot-stack
   cp docker-compose.yml compose.yml
   cp .env.example .env
   #   HP_BIND=10.8.0.2
   docker compose -f compose.yml up -d --build
   ```
   Everything except Suricata runs here: Cowrie, multipot, Dionaea, the Conpot
   OT personas, HTTP/API decoys, SNARE/TANNER, dashboard, Filebeat,
   Elasticsearch/Kibana, EveBox, and Arkime. Suricata runs on the VPS public
   interface and its logs/PCAPs are mounted/synchronized home. Details in
   [honeypot-stack README](https://github.com/Xore/honeypot-stack#readme).
2. **VPS:** the `portbridge` (raw ports) and `socat-hp-*` (HTTP) bridges are
   already in the `cgnat/vps` stack — just make sure it's up and WireGuard is
   connected. Open the firewall for the honeypot ports:
   ```bash
   sudo ufw allow 2222/tcp comment 'REAL admin SSH'
   for p in 21 22 23 25 102 1102 2102 445 502 1502 2502 1025 1433 1723 2375 2404 3306 5060 5432 5900 6379 8081 8888 9200 10001 27017 44818 50100; do
     sudo ufw allow $p/tcp; done
   for u in 161 47808 623 5060; do sudo ufw allow $u/udp; done
   ```
3. **Investigation UIs** (`honeypot`, `kibana`, `tanner`, `evebox`, and
   `arkime`) sit behind the auth portal — log in once at `auth.xore.rocks`.

---

## Part F — Verify end-to-end

```bash
# apps
curl -sI https://api.xore.rocks/health         # 200 via Cloudflare→Traefik→WG→home

# auth: hitting a protected dashboard bounces to the login page
curl -sI https://kibana.xore.rocks/            # 302 -> auth.xore.rocks/_auth/login

# honeypot raw ports (from another host)
ssh -p 22 root@<vps-ip>                        # cowrie fake shell
redis-cli -h <vps-ip> ping                     # PONG (multipot)
curl -s http://<vps-ip>:8081/                  # "Welcome to nginx!"
tftp <vps-ip> -c get README.txt                # Dionaea TFTP persona through stable UDP 69
nc -vz <vps-ip> 20000                          # DNP3 substation RTU
```

Traffic flow for any app:
```
Browser → Cloudflare (WAF/TLS) → VPS Traefik → socat → WireGuard → home app
```

---

## Deployment order (TL;DR)

1. Base infra — WireGuard, Docker, Cloudflare cert ([VPS-Guide.md](VPS-Guide.md))
2. **VPS:** `vps/` stack (Traefik + bridges)
3. **VPS:** (optional) deploy [Xore/auth-backend](https://github.com/Xore/auth-backend) for SSO — see Part B
4. Cloudflare DNS records (proxied)
5. **Home:** each example app stack you want
6. **Home:** `honeypot-stack/` (after moving real SSH to 2222); its Compose
   dependency gate validates/applies personas before sensors start
7. Verify, then run `scripts/harden-vps.sh --apply` and `harden-homeserver.sh --apply`

> Hardening the VPS changes the SSH port to 2222 — open a second SSH session
> before applying, and mind the honeypot already owns port 22.
