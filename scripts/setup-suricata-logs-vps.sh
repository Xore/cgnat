#!/usr/bin/env bash
# setup-suricata-logs-vps.sh
# Run on the VPS.
# Creates the Suricata log directory and configures it for sshfs access
# from the home server over WireGuard.
#
# Usage: sudo bash setup-suricata-logs-vps.sh

set -euo pipefail

LOG_DIR="/opt/stacks/honeypot-stack/logs/suricata"
WG_HOME_IP="10.8.0.2"   # WireGuard IP of the home server
SSH_PORT="${SSH_PORT:-2222}" # management SSH port used by the matching home script

echo "[1/4] Creating Suricata log directory..."
mkdir -p "${LOG_DIR}"
chmod 755 "${LOG_DIR}"

echo "[2/4] Ensuring OpenSSH server is installed..."
if ! command -v sshd &>/dev/null; then
  apt-get update -qq
  apt-get install -y --no-install-recommends openssh-server
fi

echo "[3/4] Allowing sshfs (sftp subsystem) in sshd..."
if ! grep -q '^Subsystem.*sftp' /etc/ssh/sshd_config; then
  echo 'Subsystem sftp /usr/lib/openssh/sftp-server' >> /etc/ssh/sshd_config
  systemctl reload sshd
  echo "  -> sftp subsystem added and sshd reloaded."
else
  echo "  -> sftp subsystem already present, skipping."
fi

echo "[4/4] Summary"
cat <<EOF

  VPS log dir : ${LOG_DIR}
  Home server : ${WG_HOME_IP}

  Next step: run setup-suricata-logs-home.sh on the HOME SERVER.
  It will mount this directory read-only via sshfs over WireGuard.

  Make sure the home server's root public key is in:
    /root/.ssh/authorized_keys  (on this VPS)
EOF
