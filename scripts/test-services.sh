#!/usr/bin/env bash
# VPS connectivity check for the current /root/vps deployment.
# Usage: DOMAIN=xore.rocks ./test-services.sh [PUBLIC_IP_OR_HOST]

HOST="${1:-127.0.0.1}"
DOMAIN="${DOMAIN:-xore.rocks}"
PASS=0; FAIL=0; WARN=0

GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'
CYAN='\033[0;36m'; NC='\033[0m'

pass() { echo -e "  ${GREEN}[PASS]${NC} $*"; ((PASS++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $*"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $*"; ((WARN++)); }
info() { echo -e "\n${CYAN}$*${NC}"; }
skip() { echo -e "  ${YELLOW}[SKIP]${NC} $*"; }

tcp_open() {
  local host="$1" port="$2" seconds="${3:-3}"
  timeout "$seconds" bash -c "</dev/tcp/$host/$port" 2>/dev/null
}

curl_check() {
  local label="$1" url="$2" code
  shift 2
  code=$(curl -sk --max-time 8 -o /dev/null -w '%{http_code}' "$@" "$url" 2>/dev/null)
  case "$code" in
    2??|3??|401|403) pass "$label - HTTP $code" ;;
    4??)             warn "$label - HTTP $code (route answered; application rejected the request)" ;;
    5??)             fail "$label - HTTP $code (proxy or backend failure)" ;;
    *)               fail "$label - no HTTP response (got '$code')" ;;
  esac
}

tcp_check() {
  local label="$1" port="$2"
  if tcp_open "$HOST" "$port"; then
    pass "$label - TCP:$port open"
  else
    fail "$label - TCP:$port unreachable"
  fi
}

banner_check() {
  local label="$1" port="$2" expected="$3" banner
  banner=$(timeout 3 bash -c "cat </dev/tcp/$HOST/$port" 2>/dev/null | head -c 256)
  if grep -qi "$expected" <<<"$banner"; then
    pass "$label - TCP:$port banner contains '$expected'"
  elif tcp_open "$HOST" "$port"; then
    pass "$label - TCP:$port open (no expected banner)"
  else
    fail "$label - TCP:$port unreachable"
  fi
}

udp_check() {
  local label="$1" port="$2"
  if command -v nc >/dev/null 2>&1; then
    printf '' | nc -u -w2 "$HOST" "$port" >/dev/null 2>&1 || true
    pass "$label - UDP:$port probe sent (UDP cannot confirm a response generically)"
  else
    skip "$label - UDP:$port (nc unavailable)"
  fi
}

echo -e "${CYAN}VPS service connectivity test - raw host: $HOST - HTTPS domain: $DOMAIN${NC}"

info "[Traefik entrypoints]"
curl_check "HTTP to HTTPS" "http://$HOST/" -L --max-redirs 1
curl_check "HTTPS entrypoint" "https://$HOST/"

# These services are reachable inside Docker's proxy network, not through
# localhost ports. Test the actual routes used by clients and Traefik.
info "[Public HTTPS routes]"
curl_check "Root/homepage" "https://$DOMAIN/"
curl_check "Auth portal health" "https://auth.$DOMAIN/_auth/health"
curl_check "Uptime Kuma" "https://status.$DOMAIN/"
curl_check "Home Assistant upstream" "https://ha.$DOMAIN/"

info "[Authenticated investigation and honeypot routes]"
curl_check "SNARE HTTP honeypot" "https://snare.$DOMAIN/"
curl_check "HTTP decoy" "https://decoy.$DOMAIN/"
curl_check "Honeypot dashboard" "https://honeypot.$DOMAIN/"
curl_check "Kibana" "https://kibana.$DOMAIN/"
curl_check "Tanner" "https://tanner.$DOMAIN/"
curl_check "EveBox" "https://evebox.$DOMAIN/"
curl_check "Arkime" "https://arkime.$DOMAIN/"

info "[Game ports]"
tcp_check "Minecraft" 25565
udp_check "CS2/Valheim" 27015

info "[Raw honeypot TCP ports]"
banner_check "FTP" 21 "220"
banner_check "SSH" 22 "SSH"
tcp_check "Telnet" 23
banner_check "SMTP" 25 "220"
tcp_check "Siemens S7" 102
tcp_check "MSRPC endpoint mapper" 135
tcp_check "S7-1200" 1102
tcp_check "S7-1500" 2102
tcp_check "SMB" 445
tcp_check "Modbus" 502
tcp_check "S7-1200 Modbus" 1502
tcp_check "S7-1500 Modbus" 2502
tcp_check "Kamstrup meter" 1025
tcp_check "PPTP" 1723
tcp_check "MQTT" 1883
tcp_check "Docker API" 2375
tcp_check "IEC-104" 2404
tcp_check "MSSQL" 1433
tcp_check "MySQL" 3306
tcp_check "SIP/VoIP" 5060
tcp_check "PostgreSQL" 5432
tcp_check "VNC" 5900
tcp_check "Redis" 6379
curl_check "HTTP honeypot" "http://$HOST:8081/"
curl_check "API/cloud honeypot" "http://$HOST:8888/v2/_catalog"
tcp_check "Elasticsearch decoy" 9200
tcp_check "JetDirect printer" 9100
tcp_check "Guardian AST" 10001
tcp_check "Memcached" 11211
tcp_check "DNP3 RTU" 20000
tcp_check "MongoDB" 27017
tcp_check "EtherNet/IP" 44818
tcp_check "Kamstrup management" 50100

info "[Raw honeypot UDP ports]"
udp_check "TFTP" 69
udp_check "SNMP" 161
udp_check "IPMI" 623
udp_check "UPnP/SSDP" 1900
udp_check "SIP/VoIP" 5060
udp_check "BACnet" 47808

info "[Local Suricata container]"
if docker inspect hp-suricata >/dev/null 2>&1; then
  status=$(docker inspect -f '{{.State.Status}}' hp-suricata 2>/dev/null)
  if [[ "$status" == "running" ]]; then
    pass "hp-suricata is running"
    rules=$(docker exec hp-suricata sh -c "grep -c '' /var/lib/suricata/rules/suricata.rules" 2>/dev/null || echo 0)
    pass "Suricata rules loaded: $rules lines"
  else
    fail "hp-suricata state: $status"
  fi
else
  skip "Suricata check (Docker unavailable or script is not running on the VPS)"
fi

total=$((PASS + FAIL + WARN))
echo -e "\n${CYAN}Results:${NC} ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$WARN warnings${NC}, $total classified checks"
[[ $FAIL -eq 0 ]]
