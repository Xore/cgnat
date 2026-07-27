# VPS stack — Traefik, socat/portbridge, Suricata

Everything that runs on the VPS: Traefik (reverse proxy), the socat and
portbridge forwards into the WireGuard tunnel (`10.8.0.2`), and Suricata
sniffing the public interface. Deploy with:

```bash
cp .env.example .env   # fill in SURICATA_* values
docker compose up -d
```

See [`../docs/STACK-SETUP.md`](../docs/STACK-SETUP.md) for the full setup.

## Optional: auth portal (SSO / forward-auth)

The SSO login that protects this stack's admin surfaces is **not part of this
repository**. It lives in its own repo:

**https://github.com/Xore/auth-backend**

Deploy it from there with its own install files — `docker-compose.yml` and
`.env.example` (it joins this stack's `proxy` network as the `auth-portal`
container):

```bash
git clone https://github.com/Xore/auth-backend
cd auth-backend
cp .env.example .env   # set COOKIE_SECRET, AUTH_PASSWORD, ... (see that repo)
docker compose up -d --build auth-portal
```

Then expose the login page by adding this router + service to
[`traefik/dynamic.yml`](traefik/dynamic.yml):

```yaml
http:
  routers:
    auth-portal:
      rule: "Host(`auth.xore.rocks`)"
      entryPoints: [websecure]
      service: auth-portal
      tls:
        options: modern
      # no forward-auth on this router — that would loop the login page
      middlewares: [security-headers, rate-limit-auth]
  services:
    auth-portal:
      loadBalancer:
        servers:
          - url: "http://auth-portal:4181"
        passHostHeader: true
```

The `forward-auth` middleware is already defined in `dynamic.yml` and attached
to the honeypot UI routers (dashboard, kibana, tanner, evebox, arkime). It is
**fail-closed**: those routers return 5xx until `auth-portal` is running. To
protect any additional router, add `forward-auth` to its `middlewares` list.
