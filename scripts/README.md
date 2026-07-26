# Hardening Scripts

Two scripts that **check and optionally apply** every hardening step from the guide.
Both are safe to re-run at any time.

| Script | Target | What it covers |
|--------|--------|----------------|
| `harden-vps.sh` | VPS | SSH port change, UFW (Cloudflare IPs), fail2ban, sysctl, Docker daemon, unattended-upgrades, fd limits |
| `harden-homeserver.sh` | Home server | SSH hardening, UFW, fail2ban, sysctl, Docker daemon, WireGuard keepalive check, unattended-upgrades |

## Usage

```bash
# Check only — shows status of every item, applies nothing
bash harden-vps.sh --check

# Check and apply everything
sudo bash harden-vps.sh --apply

# Same for home server
bash harden-homeserver.sh --check
sudo bash harden-homeserver.sh --apply
```

## Flags

| Flag | Behaviour |
|------|-----------|
| `--check` | Audit mode. Prints PASS / WARN / FAIL for each item. No changes made. |
| `--apply` | Applies all missing/incorrect settings. Already-correct items are skipped. |
| `--ssh-port <n>` | Override SSH port (default: `2222` for VPS, `22` for home server) |
| `--wg-port <n>` | Override WireGuard port (default: `51820`, VPS script only) |
| `--honeypot` | Audit/apply the current public raw honeypot ports (VPS only) |

## Output

Color-coded per item:
- ✅ `PASS` — already correctly configured
- ⚠️ `WARN` — present but not ideal (shown in `--check`, fixed in `--apply`)
- ❌ `FAIL` — missing or incorrect (shown in `--check`, fixed in `--apply`)

## Safety Notes

- The VPS script changes the SSH port. **Open a second SSH session before running `--apply`** so you don't lock yourself out.
- UFW rules for Cloudflare IPs are fetched live from `https://www.cloudflare.com/ips-v4`.
- The scripts never touch WireGuard key material.
- `--check` is fully read-only and requires no sudo.
- The VPS Compose project is `/root/vps/docker-compose.yml` (plain Compose, no
  Dockge). The home honeypot stack is `/opt/stacks/honeypot-stack/compose.yml`.
- Dashboard, Kibana, Tanner, EveBox, Arkime, and SNARE remain behind
  authenticated Traefik HTTPS; their backend ports are not opened by UFW.

## Diagnostics and log mounts

- `test-services.sh [VPS-IP]` checks every current raw honeypot/OT port and the
  real HTTPS routes; set `DOMAIN=xore.rocks` when using another domain.
- `debug-backends.sh` runs on the VPS and probes required home backends over
  WireGuard. Optional application stacks are warnings rather than hard failures.
- `debug-traefik.sh [DOMAIN]` runs on the VPS and checks the current route list,
  home backend ports, integrated auth container, and end-to-end HTTPS status.
- `home/debug-homeserver.sh` in the
  [`honeypot-stack`](https://github.com/Xore/honeypot-stack) repository runs on
  the home server and audits every long-running service from the authoritative
  `compose.yml`, then probes WireGuard-bound ports. Pass the VPS target
  explicitly; management SSH defaults to port 2222.
- `setup-suricata-logs-{vps,home}.sh` and `setup-portbridge-log-home.sh` use the
  shared `/opt/stacks/honeypot-stack/logs/...` paths and management SSH port 2222.
- `suricata-mount-watcher.{sh,service}` is only a disabled home-side fallback.
  The supported live setup is the `/etc/fstab` `x-systemd.automount` installed
  by `setup-suricata-logs-home.sh`; do not enable both mechanisms.

Cowrie files under `cowrie/honeyfs/` in the honeypot repository that end in
`.sh` or `.ps1` are inert attacker-facing decoy content, not administrator
scripts.
