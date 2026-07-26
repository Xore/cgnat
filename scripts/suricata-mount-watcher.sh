#!/usr/bin/env bash
# suricata-mount-watcher.sh
# Optional HOME-SERVER fallback for the Suricata sshfs mount. The supported
# setup uses an x-systemd.automount entry created by
# setup-suricata-logs-home.sh; this watcher remains disabled by default and is
# only useful on hosts where the systemd automount repeatedly fails.

set -euo pipefail

MOUNT_TARGET="/opt/stacks/honeypot-stack/logs/suricata"
REMOTE_HOST="10.8.0.1"
REMOTE_PATH="/opt/stacks/honeypot-stack/logs/suricata"
SSH_KEY="${SSH_KEY:-/root/.ssh/strato_vps}"
SSH_PORT="${SSH_PORT:-2222}"

log() {
  printf '[%s] %s\n' "$(date --iso-8601=seconds)" "$*"
}

ensure_mount() {
  if mountpoint -q "${MOUNT_TARGET}"; then
    return 0
  fi

  log "Mount ${MOUNT_TARGET} not present, attempting sshfs remount..."

  mkdir -p "${MOUNT_TARGET}" /root/.ssh
  touch /root/.ssh/known_hosts
  chmod 700 /root/.ssh
  chmod 600 /root/.ssh/known_hosts

  ssh-keyscan -p "${SSH_PORT}" "${REMOTE_HOST}" 2>/dev/null \
    | grep -v '^#' \
    >> /root/.ssh/known_hosts || true
  sort -u /root/.ssh/known_hosts -o /root/.ssh/known_hosts || true

  sshfs \
    -o ro,allow_other,reconnect \
    -o ServerAliveInterval=15,ServerAliveCountMax=3 \
    -o StrictHostKeyChecking=yes \
    -o PasswordAuthentication=no \
    -o IdentityFile="${SSH_KEY}" \
    -o PreferredAuthentications=publickey \
    -p "${SSH_PORT}" \
    "root@${REMOTE_HOST}:${REMOTE_PATH}" \
    "${MOUNT_TARGET}" || log "sshfs remount failed"
}

log "home-side Suricata mount watcher started (fallback mode)."

while true; do
  ensure_mount
  sleep 60
done
