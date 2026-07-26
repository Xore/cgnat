#!/usr/bin/env bash
# =============================================================================
# harden-vps.sh — Hardening checker + applicator for the CGNAT VPS
# Usage: bash harden-vps.sh --check
#        sudo bash harden-vps.sh --apply [--pubkey "ssh-ed25519 AAAA..."]
#        sudo bash harden-vps.sh --apply --honeypot   # also open honeypot ports
# =============================================================================
set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────────
SSH_PORT="2222"
WG_PORT="51820"
MODE=""
# No default — pass --pubkey "ssh-ed25519 AAAA..." explicitly, or the script
# skips adding an authorized key entirely (see the PUBKEY check below).
PUBKEY=""
HONEYPOT=0

# ── Argument parsing ──────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case $1 in
    --check)     MODE="check" ;;
    --apply)     MODE="apply" ;;
    --ssh-port)  SSH_PORT="$2"; shift ;;
    --wg-port)   WG_PORT="$2";  shift ;;
    --pubkey)    PUBKEY="$2";   shift ;;
    --honeypot)  HONEYPOT=1 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
  shift
done

if [[ -z "$MODE" ]]; then
  echo "Usage: $0 --check | --apply [--ssh-port <n>] [--wg-port <n>] [--pubkey \"ssh-ed25519 AAAA...\"] [--honeypot]"
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

# ─────────────────────────────────────────────────────────────────────────────
# ufw_has_rule PORT PROTO
#   Returns 0 if UFW already has an ALLOW rule for port/proto (any direction).
#   Works regardless of whether the rule was added with or without a comment,
#   and regardless of the exact column format (`ALLOW` vs `ALLOW IN`).
# ─────────────────────────────────────────────────────────────────────────────
ufw_has_rule() {
  local port="$1" proto="$2"
  ufw status 2>/dev/null | grep -qE "^${port}/${proto}[[:space:]]"
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
check_sshd_option "PermitRootLogin"        "prohibit-password"
check_sshd_option "MaxAuthTries"           "3"
check_sshd_option "Port"                   "$SSH_PORT"
check_sshd_option "PubkeyAuthentication"   "yes"
check_sshd_option "X11Forwarding"          "no"
check_sshd_option "AllowAgentForwarding"   "no"
check_sshd_option "LoginGraceTime"         "30"

# ── authorized_keys for root ──────────────────────────────────────────────────
if [[ -n "$PUBKEY" ]]; then
  AUTH_KEYS="/root/.ssh/authorized_keys"
  if grep -qF "$PUBKEY" "$AUTH_KEYS" 2>/dev/null; then
    pass "root authorized_keys: pubkey present"
  else
    fail "root authorized_keys: pubkey missing"
    if [[ "$MODE" == "apply" ]]; then
      mkdir -p /root/.ssh
      chmod 700 /root/.ssh
      echo "$PUBKEY" >> "$AUTH_KEYS"
      chmod 600 "$AUTH_KEYS"
      pass "root authorized_keys: pubkey added"
    fi
  fi
else
  warn "No pubkey provided — skipping authorized_keys check (pass --pubkey to set one)"
fi

if [[ "$MODE" == "apply" ]]; then
  info "Restarting sshd..."
  echo ""
  echo -e "  ${YELLOW}⚠️  WARNING: SSH port is now $SSH_PORT. Make sure you have a second session open!${RESET}"
  echo ""
  systemctl restart sshd
  pass "sshd restarted"
fi

# ═════════════════════════════════════════════════════════════════════════════
section "2. UFW Firewall — Core"
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
  "ufw_has_rule ${SSH_PORT} tcp" \
  "ufw allow ${SSH_PORT}/tcp"

apply_if "UFW allow WireGuard $WG_PORT/udp" \
  "ufw_has_rule ${WG_PORT} udp" \
  "ufw allow ${WG_PORT}/udp"

CF_IPS=$(curl -sf https://www.cloudflare.com/ips-v4 2>/dev/null || echo "")
if [[ -z "$CF_IPS" ]]; then
  warn "Could not fetch Cloudflare IP list (offline?)"
else
  CF_COUNT=$(echo "$CF_IPS" | wc -l)
  UFW_CF_COUNT=$(ufw status 2>/dev/null | grep -c "443/tcp.*ALLOW" || true)
  if [[ "$UFW_CF_COUNT" -ge "$CF_COUNT" ]]; then
    pass "UFW: Cloudflare IPs allowed on :443 ($UFW_CF_COUNT rules)"
  else
    fail "UFW: Cloudflare IPs not fully configured on :443 ($UFW_CF_COUNT/$CF_COUNT)"
    if [[ "$MODE" == "apply" ]]; then
      info "Adding Cloudflare IP rules..."
      while IFS= read -r ip; do
        ufw allow from "$ip" to any port 443 proto tcp 2>/dev/null || true
      done <<< "$CF_IPS"
      pass "Cloudflare IPs added to UFW"
    fi
  fi
fi

apply_if "UFW: port 22 closed (SSH moved to $SSH_PORT)" \
  "! ufw status | grep -q '^22/tcp.*ALLOW'" \
  "ufw delete allow 22/tcp 2>/dev/null || true"

# ═════════════════════════════════════════════════════════════════════════════
section "2b. UFW Firewall — Honeypot Stack Ports"
# ═════════════════════════════════════════════════════════════════════════════
# These ports are forwarded by portbridge/socat on the VPS into the WireGuard
# tunnel toward the home-side Xore/honeypot-stack deployment.
# They must be open on the VPS public interface so internet scanners/attackers
# can reach the honeypot sensors.
#
# Pass --honeypot to --apply to add these rules, or run --check to audit them.
#
# Service map (mirrors honeypot-stack/docker-compose.yml):
#   TCP  21    — Dionaea  FTP
#   TCP  22    — Cowrie   SSH  (honeypot SSH, NOT the mgmt port)
#   TCP  23    — Cowrie   Telnet
#   TCP  25    — Multipot SMTP
#   TCP  102/1102/2102 — Conpot S7-200/S7-1200/S7-1500
#   TCP  445   — Dionaea  SMB
#   TCP  502/1502/2502 — Conpot Modbus personas
#   TCP  1433  — Dionaea  MSSQL
#   TCP  1723  — Dionaea  PPTP
#   TCP  2375  — Multipot Docker API (lure)
#   TCP  3306  — Dionaea  MySQL
#   TCP  5060  — Dionaea  SIP
#   TCP  5432  — Multipot PostgreSQL
#   TCP  5900  — Multipot VNC
#   TCP  6379  — Multipot Redis
#   TCP  8081  — http-honeypot fake nginx (HTTP)
#   TCP  8888  — API/cloud/LLM honeypot
#   TCP  9200  — Multipot Elasticsearch (lure)
#   TCP  1025/50100 — Conpot Kamstrup meter
#   TCP  2404  — Conpot IEC-104
#   TCP  10001 — Conpot Guardian AST
#   TCP  27017 — Dionaea  MongoDB
#   TCP  44818 — Conpot   EtherNet/IP
#   UDP  161   — Conpot   SNMP
#   UDP  623   — Conpot   IPMI
#   UDP  5060  — Dionaea  SIP (UDP)
#   UDP  47808 — Conpot   BACnet

# TCP honeypot ports (publicly exposed lures)
# Dashboard/Kibana/EveBox/Arkime/Tanner/SNARE are intentionally omitted here:
# they are reachable through authenticated Traefik routes on 443, not raw UFW
# openings that would bypass the auth middleware.
HP_TCP_PORTS=(21 22 23 25 102 135 445 502 1025 1102 1433 1502 1723 1883 2102 2375 2404 2502 3306 5060 5432 5900 6379 8081 8888 9100 9200 10001 11211 20000 27017 44818 50100)
# UDP honeypot ports
HP_UDP_PORTS=(69 161 623 1900 5060 47808)

if [[ "$HONEYPOT" -eq 1 ]]; then
  info "Honeypot mode — checking + applying all honeypot port rules"
fi

for port in "${HP_TCP_PORTS[@]}"; do
  if [[ "$HONEYPOT" -eq 1 ]]; then
    apply_if "UFW allow honeypot TCP $port" \
      "ufw_has_rule ${port} tcp" \
      "ufw allow ${port}/tcp comment 'honeypot'"
  else
    if ufw_has_rule "${port}" tcp; then
      pass "UFW honeypot TCP $port: open"
    else
      warn "UFW honeypot TCP $port: not open (run with --honeypot to add)"
    fi
  fi
done

for port in "${HP_UDP_PORTS[@]}"; do
  if [[ "$HONEYPOT" -eq 1 ]]; then
    apply_if "UFW allow honeypot UDP $port" \
      "ufw_has_rule ${port} udp" \
      "ufw allow ${port}/udp comment 'honeypot'"
  else
    if ufw_has_rule "${port}" udp; then
      pass "UFW honeypot UDP $port: open"
    else
      warn "UFW honeypot UDP $port: not open (run with --honeypot to add)"
    fi
  fi
done

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
F2B_CORRECT=$(grep -q "port = $SSH_PORT" "$F2B_JAIL" 2>/dev/null && echo yes || echo no)

if [[ "$F2B_CORRECT" == "yes" ]]; then
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

SYSCTL_FILE="/etc/sysctl.d/99-vps-hardening.conf"

declare -A SYSCTL_EXPECTED=(
  ["net.ipv4.ip_forward"]="1"
  ["net.ipv4.conf.all.rp_filter"]="1"
  ["net.ipv4.conf.all.accept_redirects"]="0"
  ["net.ipv4.tcp_syncookies"]="1"
  ["net.core.somaxconn"]="65535"
  ["net.ipv4.tcp_max_syn_backlog"]="65535"
  ["net.ipv4.tcp_tw_reuse"]="1"
  ["net.ipv4.tcp_fin_timeout"]="15"
  ["fs.file-max"]="2097152"
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
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.ip_local_port_range = 1024 65535
fs.file-max = 2097152
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

# FIX: Docker install uses a function so /etc/os-release is sourced at runtime,
# not when the apply_if string is interpolated at parse time.
install_docker() {
  apt-get install -y ca-certificates curl
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc
  # Source os-release HERE so UBUNTU_CODENAME/VERSION_CODENAME are available
  . /etc/os-release
  local codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
  if [[ -z "$codename" ]]; then
    echo "ERROR: could not determine Ubuntu codename from /etc/os-release" >&2
    return 1
  fi
  cat > /etc/apt/sources.list.d/docker.sources <<REPOEOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${codename}
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
REPOEOF
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

apply_if "Docker installed (official repo)" \
  "command -v docker && docker info &>/dev/null" \
  "install_docker"

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

SYSD_OVERRIDE="/etc/systemd/system/docker.service.d/override.conf"
if [[ -f "$SYSD_OVERRIDE" ]] && grep -q "LimitNOFILE=infinity" "$SYSD_OVERRIDE"; then
  pass "Docker systemd override present"
else
  fail "Docker systemd override missing (LimitNOFILE=infinity)"
  if [[ "$MODE" == "apply" ]]; then
    mkdir -p /etc/systemd/system/docker.service.d
    cat > "$SYSD_OVERRIDE" <<'EOF'
[Service]
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TimeoutStartSec=300
Restart=always
RestartSec=5
EOF
    systemctl daemon-reload && systemctl restart docker
    pass "Docker systemd override applied"
  fi
fi

# ═════════════════════════════════════════════════════════════════════════════
section "6. File Descriptor Limits"
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
section "7. Automatic Security Updates"
# ════════════════════════════════════════════════════════════════════════════

apply_if "unattended-upgrades installed" \
  "dpkg -l unattended-upgrades 2>/dev/null | grep -q '^ii'" \
  "apt-get install -y unattended-upgrades"

apply_if "unattended-upgrades enabled" \
  "systemctl is-enabled unattended-upgrades" \
  "systemctl enable unattended-upgrades && systemctl start unattended-upgrades"

if grep -q 'distro_codename}-security' /etc/apt/apt.conf.d/50unattended-upgrades 2>/dev/null; then
  pass "unattended-upgrades: security origin configured"
else
  warn "unattended-upgrades: 50unattended-upgrades may need manual review"
fi

# ═════════════════════════════════════════════════════════════════════════════
section "8. WireGuard"
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

WG_PSK="/etc/wireguard/preshared.key"
if [[ -f "$WG_PSK" ]]; then
  PSK_PERMS=$(stat -c "%a" "$WG_PSK")
  if [[ "$PSK_PERMS" == "600" ]]; then
    pass "WireGuard preshared.key chmod 600"
  else
    fail "WireGuard preshared.key permissions: $PSK_PERMS (want 600)"
    [[ "$MODE" == "apply" ]] && chmod 600 "$WG_PSK" && pass "preshared.key chmod 600 applied"
  fi
else
  warn "WireGuard preshared.key not found at $WG_PSK"
fi

# ═════════════════════════════════════════════════════════════════════════════
section "Summary"
# ═════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "  ${GREEN}PASS${RESET}: $PASS   ${YELLOW}WARN${RESET}: $WARN   ${RED}FAIL${RESET}: $FAIL"
echo ""
if [[ "$MODE" == "check" && "$FAIL" -gt 0 ]]; then
  echo -e "  Run ${BOLD}sudo bash $0 --apply${RESET} to fix all failures."
  echo -e "  Add ${BOLD}--honeypot${RESET} to also open honeypot-stack ports."
fi
if [[ "$MODE" == "apply" ]]; then
  echo -e "  ${GREEN}All hardening steps applied.${RESET}"
  echo -e "  ${YELLOW}Connect: ssh -i STRATO -p $SSH_PORT root@<vps-ip>${RESET}"
  if [[ "$HONEYPOT" -eq 1 ]]; then
    echo -e "  ${YELLOW}Honeypot ports opened on public interface.${RESET}"
  fi
fi
