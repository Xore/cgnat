#!/usr/bin/env bash
# setup-portbridge-log-home.sh
# Run on the HOME SERVER as root (sudo -i).
#
# Mounts the VPS portbridge connection-log directory read-only over WireGuard
# (sshfs) and persists it in /etc/fstab — the same pattern as the Suricata log
# mount (setup-suricata-logs-home.sh). This surfaces the real-attacker-IP
# connection log (/logs/portbridge/portbridge.json, written by portbridge on the
# VPS) to the home honeypot dashboard, so cowrie / dionaea / conpot ports get
# attributed to real IPs instead of the tunnel peer 10.8.0.1.
#
# Usage:
#   sudo bash setup-portbridge-log-home.sh
# Override defaults via env vars:
#   SSH_KEY=/root/.ssh/strato_vps SSH_PORT=2222 sudo -E bash setup-portbridge-log-home.sh

set -euo pipefail

VPS_WG_IP="10.8.0.1"                                             # WireGuard IP of the VPS
MOUNT_TARGET="/opt/stacks/honeypot-stack/logs/portbridge"        # local mountpoint (dashboard reads /logs recursively)
REMOTE_PATH="/opt/stacks/honeypot-stack/logs/portbridge"         # portbridge CONN_LOG dir on the VPS
SSH_KEY="${SSH_KEY:-/root/.ssh/strato_vps}"                      # key the home root uses to reach the VPS
SSH_PORT="${SSH_PORT:-2222}"                                     # real admin SSH port on the VPS

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: run as root (sudo -i, then bash $0)." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
echo "[1/6] Ensuring sshfs is installed..."
if ! command -v sshfs &>/dev/null; then
  apt-get update -qq
  apt-get install -y --no-install-recommends sshfs
else
  echo "  -> sshfs already installed."
fi

# ---------------------------------------------------------------------------
echo "[2/6] Ensuring user_allow_other in fuse.conf..."
if ! grep -q '^user_allow_other' /etc/fuse.conf 2>/dev/null; then
  echo 'user_allow_other' >> /etc/fuse.conf
  echo "  -> added."
else
  echo "  -> already set."
fi

# ---------------------------------------------------------------------------
echo "[3/6] Creating mountpoint ${MOUNT_TARGET}..."
mkdir -p "${MOUNT_TARGET}"

# ---------------------------------------------------------------------------
echo "[4/6] Pre-accepting VPS host key..."
mkdir -p /root/.ssh
touch /root/.ssh/known_hosts
chmod 700 /root/.ssh
chmod 600 /root/.ssh/known_hosts
ssh-keyscan -p "${SSH_PORT}" "${VPS_WG_IP}" 2>/dev/null \
  | grep -v '^#' >> /root/.ssh/known_hosts || true
sort -u /root/.ssh/known_hosts -o /root/.ssh/known_hosts || true

# ---------------------------------------------------------------------------
echo "[5/6] Mounting ${VPS_WG_IP}:${REMOTE_PATH} -> ${MOUNT_TARGET}..."
if mountpoint -q "${MOUNT_TARGET}"; then
  echo "  -> already mounted, remounting..."
  umount "${MOUNT_TARGET}" 2>/dev/null || fusermount -u "${MOUNT_TARGET}" 2>/dev/null || true
fi

sshfs \
  -o ro,allow_other,reconnect,cache=no \
  -o ServerAliveInterval=15,ServerAliveCountMax=3 \
  -o StrictHostKeyChecking=yes \
  -o PasswordAuthentication=no \
  -o IdentityFile="${SSH_KEY}" \
  -o PreferredAuthentications=publickey \
  -p "${SSH_PORT}" \
  "root@${VPS_WG_IP}:${REMOTE_PATH}" \
  "${MOUNT_TARGET}"

mountpoint "${MOUNT_TARGET}"
echo "  -> mounted."

# ---------------------------------------------------------------------------
echo "[6/6] Persisting mount in /etc/fstab..."
# NOTE: deliberately NO x-systemd.automount. An autofs direct mount can only be
# triggered by processes with CAP_SYS_ADMIN over the host mount namespace —
# Docker containers get EPERM ("Operation not permitted") instead, which left
# the dashboard unable to read portbridge.json and every sensor stuck on the
# tunnel peer IP 10.8.0.1. The mount must be established before
# `docker compose up` so the containers' bind mounts capture it (the
# dashboard's /logs volume uses rslave propagation so later host-side remounts
# still propagate in).
# cache=no: the dashboard re-reads the tail of portbridge.json every minute to
# join cowrie/dionaea sessions against real attacker IPs; sshfs data caching
# would delay fresh entries and leave new events stuck on 10.8.0.1.
FSTAB_LINE="root@${VPS_WG_IP}:${REMOTE_PATH}  ${MOUNT_TARGET}  fuse.sshfs  ro,allow_other,reconnect,cache=no,ServerAliveInterval=15,ServerAliveCountMax=3,IdentityFile=${SSH_KEY},port=${SSH_PORT},StrictHostKeyChecking=yes,PasswordAuthentication=no,PreferredAuthentications=publickey,_netdev  0  0"

if grep -qF "${MOUNT_TARGET}" /etc/fstab; then
  echo "  -> fstab entry already present, skipping."
else
  echo "${FSTAB_LINE}" >> /etc/fstab
  echo "  -> fstab entry added."
fi

cat <<EOF

========================================
  Done.

  Mount  : ${MOUNT_TARGET}
  Source : root@${VPS_WG_IP}:${REMOTE_PATH}
  Key    : ${SSH_KEY}   Port: ${SSH_PORT}
  Mode   : read-only, auto-reconnect, mounted at boot via fstab (_netdev)

  The honeypot dashboard reads /logs recursively, so
  portbridge.json now appears within ~15s and real
  attacker IPs will be attributed to cowrie / dionaea /
  conpot ports (not just multipot).

  Verify:
    tail -f ${MOUNT_TARGET}/portbridge.json
    curl -s http://10.8.0.2:19090/ips | head

  Unmount:  fusermount -u ${MOUNT_TARGET}
  Remount:  mount ${MOUNT_TARGET}
========================================
EOF
