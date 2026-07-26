#!/usr/bin/env bash
# setup-suricata-logs-home.sh
# Run on the HOME SERVER.
# Installs sshfs, mounts the VPS Suricata log dir read-only over WireGuard,
# and persists the mount in /etc/fstab.
#
# Usage: sudo bash setup-suricata-logs-home.sh
# Override defaults via env vars:
#   SSH_KEY="/root/.ssh/strato_vps" SSH_PORT="2222" bash setup-suricata-logs-home.sh

set -euo pipefail

VPS_WG_IP="10.8.0.1"     # WireGuard IP of the VPS
MOUNT_TARGET="/opt/stacks/honeypot-stack/logs/suricata"
REMOTE_PATH="/opt/stacks/honeypot-stack/logs/suricata"
SSH_KEY="${SSH_KEY:-/root/.ssh/strato_vps}"   # Key used to authenticate to the VPS
SSH_PORT="${SSH_PORT:-2222}"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: run as root (sudo -i, then bash $0)." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
echo "[1/6] Installing sshfs..."
if ! command -v sshfs &>/dev/null; then
  apt-get update -qq
  apt-get install -y --no-install-recommends sshfs
else
  echo "  -> sshfs already installed."
fi

# ---------------------------------------------------------------------------
echo "[2/6] Enabling user_allow_other in fuse.conf..."
if ! grep -q '^user_allow_other' /etc/fuse.conf 2>/dev/null; then
  echo 'user_allow_other' >> /etc/fuse.conf
  echo "  -> user_allow_other added."
else
  echo "  -> user_allow_other already set."
fi

# ---------------------------------------------------------------------------
echo "[3/6] Creating mount point..."
mkdir -p "${MOUNT_TARGET}"

# ---------------------------------------------------------------------------
echo "[4/6] Accepting VPS host key (first-time only)..."
# Pre-accept the host key so sshfs never prompts interactively
mkdir -p /root/.ssh
touch /root/.ssh/known_hosts
chmod 700 /root/.ssh
chmod 600 /root/.ssh/known_hosts
ssh-keyscan -p "${SSH_PORT}" "${VPS_WG_IP}" 2>/dev/null \
  | grep -v '^#' \
  >> /root/.ssh/known_hosts
# Deduplicate
sort -u /root/.ssh/known_hosts -o /root/.ssh/known_hosts
echo "  -> Host key accepted."

# ---------------------------------------------------------------------------
echo "[5/6] Mounting ${VPS_WG_IP}:${REMOTE_PATH} -> ${MOUNT_TARGET}..."

# Unmount first if already mounted (e.g. re-run)
if mountpoint -q "${MOUNT_TARGET}"; then
  echo "  -> Already mounted, unmounting first..."
  umount "${MOUNT_TARGET}" 2>/dev/null || fusermount -u "${MOUNT_TARGET}"
fi

sshfs \
  -o ro,allow_other,reconnect \
  -o ServerAliveInterval=15,ServerAliveCountMax=3 \
  -o StrictHostKeyChecking=yes \
  -o PasswordAuthentication=no \
  -o IdentityFile="${SSH_KEY}" \
  -o PreferredAuthentications=publickey \
  -p "${SSH_PORT}" \
  "root@${VPS_WG_IP}:${REMOTE_PATH}" \
  "${MOUNT_TARGET}"

echo "  -> Mounted successfully."
mountpoint "${MOUNT_TARGET}"

# ---------------------------------------------------------------------------
echo "[6/6] Persisting mount in /etc/fstab..."

FSTAB_LINE="root@${VPS_WG_IP}:${REMOTE_PATH}  ${MOUNT_TARGET}  fuse.sshfs  ro,allow_other,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3,IdentityFile=${SSH_KEY},port=${SSH_PORT},StrictHostKeyChecking=yes,PasswordAuthentication=no,PreferredAuthentications=publickey,_netdev,x-systemd.automount  0  0"

if grep -qF "${MOUNT_TARGET}" /etc/fstab; then
  echo "  -> fstab entry already exists, skipping."
else
  echo "${FSTAB_LINE}" >> /etc/fstab
  echo "  -> fstab entry added."
fi

cat <<EOF

========================================
  Done!

  Mount  : ${MOUNT_TARGET}
  Source : root@${VPS_WG_IP}:${REMOTE_PATH}
  Key    : ${SSH_KEY}
  Port   : ${SSH_PORT}
  Mode   : read-only, auto-reconnect

  EveBox and Filebeat will now find
  eve.json at:
    ${MOUNT_TARGET}/eve.json

  To unmount manually:
    fusermount -u ${MOUNT_TARGET}

  To remount after reboot (if fstab fails):
    mount ${MOUNT_TARGET}
========================================
EOF
