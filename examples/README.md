# Examples

Examples for exposing services through the CGNAT VPS gateway. Application
folders generally contain a home-side `docker-compose.yml` and a `README.md`.
SSO/forward-auth is not one of these examples — it's an optional add-on repo,
[Xore/auth-backend](https://github.com/Xore/auth-backend).

| Example | Port | Description |
|---------|------|-------------|
| [reverse-proxy](./reverse-proxy/) | any | Forward traffic to any upstream (no app container needed) |
| [uptime-kuma](./uptime-kuma/) | 3001 | Self-hosted uptime monitoring dashboard |
| [cowrie-gpu](./cowrie-gpu/) | — | Cowrie SSH/Telnet honeypot with a fake GPU-equipped host persona |
| [honeypot-stack](https://github.com/Xore/honeypot-stack) | 30+ TCP/UDP surfaces | Separate public repository: home Dockge stack + VPS Portbridge/Suricata, Cowrie, multipot, Dionaea, S7/OT Conpot personas, HTTP/API, SNARE/TANNER, dashboard, payload/script analysis, ELK, EveBox and Arkime |

## Usage Pattern

Every example follows the same 4-step pattern:

```
1. Home: app container + socat (bind=10.8.0.2)
2. VPS:  socat bridge (proxy network)
3. VPS:  Traefik router + service in dynamic.yml
4. CF:   A record (orange cloud, proxied)
```

See the [full guide](../docs/VPS-Guide.md) for the complete setup.

> cowrie-gpu is the exception to the simple HTTP pattern: raw TCP/UDP
> reaches VPS Portbridge and crosses WireGuard; authenticated web investigation
> routes use Traefik. Suricata captures on the VPS before forwarding.
