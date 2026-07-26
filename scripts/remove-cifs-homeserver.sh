#!/usr/bin/env bash
# remove-cifs-homeserver.sh
# Run on the HOME SERVER.
# Removes any CIFS (Samba/SMB) mounts, their fstab entries, and optionally
# uninstalls the cifs-utils package.
#
# Usage: sudo bash remove-cifs-homeserver.sh
# Options:
#   UNINSTALL_PKG=1 bash remove-cifs-homeserver.sh   # also remove cifs-utils

set -euo pipefail

UNINSTALL_PKG="${UNINSTALL_PKG:-0}"

# ---------------------------------------------------------------------------
echo "[1/4] Detecting active CIFS mounts..."
CIFS_MOUNTS=$(awk '$3 == "cifs" { print $2 }' /proc/mounts || true)

if [[ -z "${CIFS_MOUNTS}" ]]; then
  echo "  -> No active CIFS mounts found."
else
  while IFS= read -r MOUNTPOINT; do
    echo "  -> Unmounting: ${MOUNTPOINT}"
    umount -l "${MOUNTPOINT}" && echo "     Done." || echo "     WARNING: failed to unmount ${MOUNTPOINT}"
  done <<< "${CIFS_MOUNTS}"
fi

# ---------------------------------------------------------------------------
echo "[2/4] Removing CIFS entries from /etc/fstab..."
if grep -q 'cifs' /etc/fstab 2>/dev/null; then
  # Backup first
  cp /etc/fstab /etc/fstab.bak.$(date +%Y%m%d%H%M%S)
  # Remove all lines that reference cifs
  sed -i '/\bcifs\b/d' /etc/fstab
  echo "  -> CIFS entries removed. Backup saved as /etc/fstab.bak.*"
else
  echo "  -> No CIFS entries found in /etc/fstab."
fi

# ---------------------------------------------------------------------------
echo "[3/4] Reloading systemd daemon to pick up fstab changes..."
systemctl daemon-reload
echo "  -> Done."

# ---------------------------------------------------------------------------
echo "[4/4] Package cleanup..."
if [[ "${UNINSTALL_PKG}" == "1" ]]; then
  if dpkg -l cifs-utils &>/dev/null 2>&1; then
    apt-get remove -y --purge cifs-utils
    apt-get autoremove -y
    echo "  -> cifs-utils removed."
  else
    echo "  -> cifs-utils not installed, skipping."
  fi
else
  echo "  -> Skipping cifs-utils removal (set UNINSTALL_PKG=1 to also remove the package)."
fi

cat <<EOF

========================================
  Done!

  All CIFS mounts have been unmounted
  and removed from /etc/fstab.

  To also remove the cifs-utils package:
    UNINSTALL_PKG=1 bash remove-cifs-homeserver.sh

  A timestamped fstab backup was created
  at /etc/fstab.bak.* if changes were made.
========================================
EOF
