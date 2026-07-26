# CGNAT VPS Gateway

Expose home server services through a VPS using WireGuard, Traefik, socat, and Cloudflare — even behind CGNAT.

> **Infrastructure guide** (WireGuard, Docker, Cloudflare, hardening): [docs/VPS-Guide.md](docs/VPS-Guide.md)
> **Deploy-the-whole-stack checklist** (Traefik, apps, honeypot, optional auth): [docs/STACK-SETUP.md](docs/STACK-SETUP.md)

This repo is a **standalone CGNAT tunnel + reverse-proxy setup** — WireGuard,
Traefik, socat, Cloudflare. It has no auth-backend coupling. Two optional
add-ons live in their own repos and can be dropped in when needed:

- [Xore/auth-backend](https://github.com/Xore/auth-backend) — SSO/forward-auth
  portal for any admin surface on this stack (lockout, 2FA, passkeys, credential
  recovery docs)
- [Xore/www](https://github.com/Xore/www) — the personal homepage example that
  used to live in `examples/`

## Current deployment paths

- VPS: plain Docker Compose at `/root/vps/docker-compose.yml` (Traefik,
  Portbridge, Suricata, and all socat bridges). Dockge is not used.
- Home honeypot: Dockge stack at `/opt/stacks/honeypot-stack/compose.yml`.
- The reusable CGNAT gateway remains in `vps/`. The complete honeypot
  deployment lives in the public
  [`Xore/honeypot-stack`](https://github.com/Xore/honeypot-stack) repository.

---

## Folder Structure

```
cgnat/
├── README.md                                    # This file
├── docs/
│   └── VPS-Guide.md                             # Complete setup guide
├── vps/
│   ├── docker-compose.yml                       # Traefik + socat bridges on VPS
│   └── traefik/
│       ├── traefik.yml                          # Traefik static config
│       └── dynamic.yml                          # Routing rules (add new services here)
├── wireguard/
│   └── wg0-vps.conf.example                     # WireGuard server config template
├── scripts/
│   ├── README.md                                # Script usage docs
│   ├── harden-vps.sh                            # VPS hardening checker + applicator
│   └── harden-homeserver.sh                     # Home server hardening checker + applicator
└── examples/
    ├── README.md                                # Examples index
    ├── reverse-proxy/                           # Passthrough to any LAN host (no app container)
    │   ├── docker-compose.yml
    │   └── README.md
    ├── uptime-kuma/                             # Self-hosted uptime monitoring
    │   ├── docker-compose.yml
    │   └── README.md
    └── cowrie-gpu/                              # Cowrie SSH/Telnet honeypot, fake GPU host persona
```

---

## Quick Start

1. Read the **[full guide](docs/VPS-Guide.md)**
2. Set up the WireGuard tunnel using [`wireguard/`](wireguard/) as the VPS-side template
3. Deploy the VPS stack: `cd /root/vps && docker compose -f docker-compose.yml up -d`
4. Deploy each selected home example as its own Dockge stack under `/opt/stacks/`.
   For the honeypot, clone
   [`Xore/honeypot-stack`](https://github.com/Xore/honeypot-stack) and deploy
   its `docker-compose.yml` as the authoritative
   `/opt/stacks/honeypot-stack/compose.yml`.
5. Add DNS record in Cloudflare
6. Pick an **[example](examples/)** and wire it in

---

## Examples

| Example | Port | Description |
|---------|------|-------------|
| [reverse-proxy](examples/reverse-proxy/) | any | Forward traffic to any upstream (no app container needed) |
| [uptime-kuma](examples/uptime-kuma/) | 3001 | Self-hosted uptime monitoring dashboard |
| [cowrie-gpu](examples/cowrie-gpu/) | — | Cowrie SSH/Telnet honeypot with a fake GPU-equipped host persona |

Auth & security:
[Xore/auth-backend](https://github.com/Xore/auth-backend) (optional add-on repo — hardened Traefik forward-auth SSO at auth.<domain> — lockout, 2FA, bot traps) ·
[honeypot-stack](https://github.com/Xore/honeypot-stack) (separate public
repository containing the home Dockge stack + VPS gateway:
Cowrie, multipot, Dionaea, six Conpot/OT personas, HTTP/API decoys,
SNARE/TANNER, native AdminLTE 4.1.0/Bootstrap operations frontend, GeoIP,
payload/script risk and IOC analysis, session replay, ATT&CK Enterprise/ICS
mapping, campaign/infrastructure correlation, runtime and ingestion health,
Filebeat/Elasticsearch/Kibana, real offline YARA triage, durable alert and
intelligence state, Prometheus metrics, tested backups, an optional isolated
KVM/libvirt malware lab, EveBox and Arkime; Suricata runs on
the VPS public interface)

Every example includes:
- A ready-to-run `docker-compose.yml` with a socat bridge
- A `README.md` with quick start commands and a Traefik `dynamic.yml` snippet

---

## Hardening Scripts

| Script | Target | Run |
|--------|--------|-----|
| [scripts/harden-vps.sh](scripts/harden-vps.sh) | VPS | `sudo bash scripts/harden-vps.sh --apply` |
| [scripts/harden-homeserver.sh](scripts/harden-homeserver.sh) | Home server | `sudo bash scripts/harden-homeserver.sh --apply` |

Both scripts support `--check` (audit only, no changes) and `--apply` (fix everything).
See [scripts/README.md](scripts/README.md) for full usage.

> ⚠️ Open a second SSH session before running `--apply` on the VPS — it changes the SSH port to `2222`.

---

## Architecture

```
Internet → Cloudflare (WAF/CDN) → VPS
  Traefik :443 → socat → WireGuard tunnel
    → Home Server socat → App container
```

See [docs/VPS-Guide.md § Architecture Overview](docs/VPS-Guide.md#1-architecture-overview) for the full traffic flow diagram.
