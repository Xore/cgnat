#!/usr/bin/env bash
# =============================================================================
# harden-homeserver.sh — Hardening checker + applicator for the home server
# Usage: bash harden-homeserver.sh --check
#        sudo bash harden-homeserver.sh --apply
# =============================================================================
set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
SSH_PORT="22"   # Home server keeps port 22 (not publicly exposed)
MODE=""

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --check) MODE="check" ;;
    --apply) MODE="apply" ;;
    --ssh-port) SSH_PORT="$2"; shift ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
  shift
done

if [[ -z "$MODE" ]]; then
  echo "Usage: $0 --check | --apply [--ssh-port <n>]"
  exit 1
fi

if [[ "$MODE" == "apply" && "$EUID" -ne 0 ]]; then
  echo "--apply requires root. Run: sudo bash $0 --apply"
  exit 1
fi

# ── Colour helpers ────────────────────────────────────────────────────────────
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
BOLD=$'\033[1m'; RESET=$'\033[0m'

PASS=0; WARN=0; FAIL=0

pass()  { echo -e "  ${GREEN}✅ PASS${RESET}  $*"; (( PASS++ ))  || true; }
warn()  { echo -e "  ${YELLOW}⚠️  WARN${RESET}  $*"; (( WARN++ ))  || true; }
fail()  { echo -e "  ${RED}❌ FAIL${RESET}  $*"; (( FAIL++ ))  || true; }
info()  { echo -e "  ${BOLD}     ℹ️ ${RESET}  $*"; }
section(){ echo -e "\n${BOLD}══ $* ══${RESET}"; }

apply_if() {
  local desc="$1" check="$2" apply_cmd="$3"
  if eval "$check" &>/dev/null; then
    pass "$desc"
  else
    fail "$desc"
    if [[ "$MODE" == "apply" ]]; then
      info "Applying: $desc"
      eval "$apply_cmd"
      pass "$desc (applied)"
    fi
  fi
}

# ═════════════════════════════════════════════════════════════════════════════
section "1. SSH Hardening"
# ═════════════════════════════════════════════════════════════════════════════

SSHD_CFG="/etc/ssh/sshd_config"

check_sshd_option() {
  local key="$1" expected="$2"
  local current
  current=$(sshd -T 2>/dev/null | awk -v k="${key,,}" 'tolower($1)==k{print $2}' | tail -1)
  if [[ "${current,,}" == "${expected,,}" ]]; then
    pass "sshd: $key = $expected"
  else
    fail "sshd: $key should be '$expected' (current: '${current:-unset}')"
    if [[ "$MODE" == "apply" ]]; then
      sed -i "/^[[:space:]]*${key}/Id" "$SSHD_CFG"
      echo "$key $expected" >> "$SSHD_CFG"
      info "Set $key $expected in $SSHD_CFG"
    fi
  fi
}

check_sshd_option "PasswordAuthentication" "no"
check_sshd_option "PermitRootLogin" "no"
check_sshd_option "MaxAuthTries" "3"
check_sshd_option "X11Forwarding" "no"
check_sshd_option "AllowAgentForwarding" "no"
check_sshd_option "LoginGraceTime" "30"
# Port kept at $SSH_PORT (default 22 for home server — not internet-exposed)
check_sshd_option "Port" "$SSH_PORT"

if [[ "$MODE" == "apply" ]]; then
  info "Restarting sshd..."
  systemctl restart sshd
  pass "sshd restarted"
fi

# ═════════════════════════════════════════════════════════════════════════════
section "2. UFW Firewall"
# ═════════════════════════════════════════════════════════════════════════════

apply_if "UFW installed" \
  "command -v ufw" \
  "apt-get install -y ufw"

apply_if "UFW enabled" \
  "ufw status | grep -q 'Status: active'" \
  "ufw --force enable"

apply_if "UFW default deny incoming" \
  "ufw status verbose | grep -q 'Default: deny (incoming)'" \
  "ufw default deny incoming"

apply_if "UFW allow SSH port $SSH_PORT" \
  "ufw status | grep -q '${SSH_PORT}/tcp'" \
  "ufw allow ${SSH_PORT}/tcp"

# Home server: only allow inbound from WireGuard VPS IP for tunnel traffic
# Allow LAN SSH as well
apply_if "UFW allow WireGuard VPS (10.8.0.1) inbound" \
  "ufw status | grep -q '10.8.0.1'" \
  "ufw allow from 10.8.0.1"

# ═════════════════════════════════════════════════════════════════════════════
section "3. Fail2ban"
# ═════════════════════════════════════════════════════════════════════════════

apply_if "fail2ban installed" \
  "command -v fail2ban-client" \
  "apt-get install -y fail2ban"

apply_if "fail2ban service running" \
  "systemctl is-active fail2ban" \
  "systemctl enable --now fail2ban"

F2B_JAIL="/etc/fail2ban/jail.d/sshd.conf"
if [[ -f "$F2B_JAIL" ]] && grep -q "port = $SSH_PORT" "$F2B_JAIL"; then
  pass "fail2ban: sshd jail configured for port $SSH_PORT"
else
  fail "fail2ban: sshd jail missing or wrong port"
  if [[ "$MODE" == "apply" ]]; then
    mkdir -p /etc/fail2ban/jail.d
    cat > "$F2B_JAIL" <<EOF
[sshd]
enabled = true
port = $SSH_PORT
maxretry = 3
bantime = 1d
findtime = 10m
EOF
    systemctl restart fail2ban
    pass "fail2ban: sshd jail written and restarted"
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
section "4. Kernel Hardening (sysctl)"
# ═════════════════════════════════════════════════════════════════════════════

SYSCTL_FILE="/etc/sysctl.d/99-homeserver-hardening.conf"

declare -A SYSCTL_EXPECTED=(
  ["net.ipv4.ip_forward"]="1"
  ["net.ipv4.conf.all.rp_filter"]="1"
  ["net.ipv4.conf.all.accept_redirects"]="0"
  ["net.ipv4.tcp_syncookies"]="1"
  ["net.core.somaxconn"]="65535"
  ["fs.inotify.max_user_instances"]="8192"
  ["fs.inotify.max_user_watches"]="524288"
  ["vm.swappiness"]="10"
  ["vm.max_map_count"]="262144"
)

SYSCTL_NEEDS_APPLY=0
for key in "${!SYSCTL_EXPECTED[@]}"; do
  expected="${SYSCTL_EXPECTED[$key]}"
  current=$(sysctl -n "$key" 2>/dev/null || echo "")
  if [[ "$current" == "$expected" ]]; then
    pass "sysctl $key = $expected"
  else
    fail "sysctl $key = ${current:-unset} (want $expected)"
    SYSCTL_NEEDS_APPLY=1
  fi
done

if [[ "$SYSCTL_NEEDS_APPLY" -eq 1 && "$MODE" == "apply" ]]; then
  info "Writing $SYSCTL_FILE..."
  cat > "$SYSCTL_FILE" <<'EOF'
net.ipv4.ip_forward = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.tcp_syncookies = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.core.somaxconn = 65535
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288
vm.swappiness = 10
vm.max_map_count = 262144
EOF
  sysctl -p "$SYSCTL_FILE"
  pass "sysctl applied"
fi

# ═════════════════════════════════════════════════════════════════════════════
section "5. Docker"
# ═════════════════════════════════════════════════════════════════════════════

apply_if "Docker installed (official repo)" \
  "command -v docker && docker info &>/dev/null" \
  "
    apt-get install -y ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    . /etc/os-release
    echo \"Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${UBUNTU_CODENAME:-$VERSION_CODENAME}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc\" > /etc/apt/sources.list.d/docker.sources
    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  "

apply_if "Docker service running" \
  "systemctl is-active docker" \
  "systemctl enable --now docker"

check_docker_daemon() {
  local key="$1" expected="$2" jq_filter="$3"
  if [[ ! -f /etc/docker/daemon.json ]]; then
    fail "Docker daemon.json missing"
    return
  fi
  local current
  current=$(python3 -c "import json,sys; d=json.load(open('/etc/docker/daemon.json')); print(${jq_filter})" 2>/dev/null || echo "")
  if [[ "$current" == "$expected" ]]; then
    pass "Docker daemon: $key = $expected"
  else
    fail "Docker daemon: $key should be '$expected' (current: '${current:-unset}')"
  fi
}

check_docker_daemon "storage-driver"    "overlay2"  "d.get('storage-driver','')"
check_docker_daemon "log-driver"        "local"     "d.get('log-driver','')"
check_docker_daemon "icc"               "False"     "str(d.get('icc',True))"
check_docker_daemon "no-new-privileges" "True"      "str(d.get('no-new-privileges',False))"
check_docker_daemon "live-restore"      "True"      "str(d.get('live-restore',False))"
check_docker_daemon "userland-proxy"    "False"     "str(d.get('userland-proxy',True))"
check_docker_daemon "BuildKit"          "True"      "str(d.get('features',{}).get('buildkit',False))"

if [[ "$MODE" == "apply" ]]; then
  info "Writing /etc/docker/daemon.json..."
  mkdir -p /etc/docker
  cat > /etc/docker/daemon.json <<'EOF'
{
  "storage-driver": "overlay2",
  "log-driver": "local",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3",
    "compress": "true"
  },
  "icc": false,
  "no-new-privileges": true,
  "live-restore": true,
  "userland-proxy": false,
  "shutdown-timeout": 15,
  "exec-opts": ["native.cgroupdriver=systemd"],
  "max-concurrent-downloads": 10,
  "max-concurrent-uploads": 10,
  "default-ulimits": {
    "nofile": { "Name": "nofile", "Hard": 65535, "Soft": 65535 }
  },
  "features": { "buildkit": true }
}
EOF
  systemctl restart docker
  pass "Docker daemon.json applied and daemon restarted"
fi

# ═════════════════════════════════════════════════════════════════════════════
section "6. WireGuard"
# ═════════════════════════════════════════════════════════════════════════════

apply_if "WireGuard installed" \
  "command -v wg" \
  "apt-get install -y wireguard wireguard-tools"

apply_if "WireGuard wg0 interface active" \
  "wg show wg0 &>/dev/null" \
  "wg-quick up wg0 2>/dev/null || true"

apply_if "WireGuard systemd service enabled" \
  "systemctl is-enabled wg-quick@wg0" \
  "systemctl enable wg-quick@wg0"

# Critical: PersistentKeepalive must be set
WG_CONF="/etc/wireguard/wg0.conf"
if [[ -f "$WG_CONF" ]]; then
  KA=$(grep -i 'PersistentKeepalive' "$WG_CONF" | awk '{print $3}' | head -1)
  if [[ -n "$KA" && "$KA" -le 25 ]]; then
    pass "WireGuard PersistentKeepalive = $KA (≤25, CGNAT safe)"
  elif [[ -n "$KA" ]]; then
    warn "WireGuard PersistentKeepalive = $KA (recommended ≤25 for CGNAT)"
    if [[ "$MODE" == "apply" ]]; then
      sed -i 's/^PersistentKeepalive.*/PersistentKeepalive = 25/' "$WG_CONF"
      wg-quick down wg0 2>/dev/null || true
      wg-quick up wg0
      pass "PersistentKeepalive set to 25 and tunnel restarted"
    fi
  else
    fail "WireGuard PersistentKeepalive not set in $WG_CONF (CRITICAL for CGNAT!)"
    if [[ "$MODE" == "apply" ]]; then
      echo "PersistentKeepalive = 25" >> "$WG_CONF"
      wg-quick down wg0 2>/dev/null || true
      wg-quick up wg0
      pass "PersistentKeepalive = 25 added and tunnel restarted"
    fi
  fi
else
  warn "WireGuard config not found at $WG_CONF (not yet set up?)"
fi

# WireGuard key permissions
WG_PRIV="/etc/wireguard/privatekey"
if [[ -f "$WG_PRIV" ]]; then
  PRIV_PERMS=$(stat -c "%a" "$WG_PRIV")
  if [[ "$PRIV_PERMS" == "600" ]]; then
    pass "WireGuard privatekey chmod 600"
  else
    fail "WireGuard privatekey permissions: $PRIV_PERMS (want 600)"
    [[ "$MODE" == "apply" ]] && chmod 600 "$WG_PRIV" && pass "WireGuard privatekey chmod 600 applied"
  fi
else
  warn "WireGuard privatekey not found at $WG_PRIV (not yet generated?)"
fi

# ═════════════════════════════════════════════════════════════════════════════
section "7. Automatic Security Updates"
# ═════════════════════════════════════════════════════════════════════════════

apply_if "unattended-upgrades installed" \
  "dpkg -l unattended-upgrades 2>/dev/null | grep -q '^ii'" \
  "apt-get install -y unattended-upgrades"

apply_if "unattended-upgrades enabled" \
  "systemctl is-enabled unattended-upgrades" \
  "systemctl enable unattended-upgrades && systemctl start unattended-upgrades"

# ═════════════════════════════════════════════════════════════════════════════
section "8. File Descriptor Limits"
# ═════════════════════════════════════════════════════════════════════════════

if grep -q "\* hard nofile 65535" /etc/security/limits.conf 2>/dev/null; then
  pass "limits.conf: nofile hard = 65535"
else
  fail "limits.conf: nofile limit not set"
  if [[ "$MODE" == "apply" ]]; then
    cat >> /etc/security/limits.conf <<'EOF'
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
EOF
    pass "limits.conf updated"
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
section "Summary"
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "  ${GREEN}PASS${RESET}: $PASS   ${YELLOW}WARN${RESET}: $WARN   ${RED}FAIL${RESET}: $FAIL"
echo ""
if [[ "$MODE" == "check" && "$FAIL" -gt 0 ]]; then
  echo -e "  Run ${BOLD}sudo bash $0 --apply${RESET} to fix all failures."
fi
if [[ "$MODE" == "apply" ]]; then
  echo -e "  ${GREEN}All hardening steps applied.${RESET}"
fi
