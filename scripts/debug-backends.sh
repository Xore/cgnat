#!/usr/bin/env bash
# Probe current Traefik backends directly from the VPS over WireGuard.
# Run on the VPS. Optional: HOME_WG_IP=10.8.0.2 ./debug-backends.sh

WG="${HOME_WG_IP:-10.8.0.2}"
PASS=0; FAIL=0; WARN=0
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

pass() { echo -e "  ${GREEN}[PASS]${NC} $*"; ((PASS++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $*"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $*"; ((WARN++)); }
info() { echo -e "\n${CYAN}$*${NC}"; }

probe() {
  local host="$1" port="$2" label="$3" path="${4:-/}" code
  code=$(curl -s --max-time 6 -o /dev/null -w '%{http_code}' "http://${host}:${port}${path}" 2>/dev/null)
  case "$code" in
    1??|2??|3??|401|403|404) pass "$label - $host:$port returned HTTP $code" ;;
    5??)                     fail "$label - $host:$port returned HTTP $code" ;;
    000|'')                  fail "$label - $host:$port did not answer HTTP" ;;
    *)                       warn "$label - $host:$port returned HTTP $code" ;;
  esac
}

optional_probe() {
  local host="$1" port="$2" label="$3" path="${4:-/}"
  if timeout 3 bash -c "</dev/tcp/$host/$port" 2>/dev/null; then
    probe "$host" "$port" "$label" "$path"
  else
    warn "$label - $host:$port is not deployed/running"
  fi
}

echo -e "${CYAN}Backend layer-7 probe - home WireGuard address: $WG${NC}"

info "[Required home honeypot and investigation services]"
probe "$WG" 19090 "Honeypot dashboard"
probe "$WG" 19601 "Kibana"
probe "$WG" 19636 "EveBox"
probe "$WG" 19080 "Arkime"
probe "$WG" 19091 "Tanner web"
probe "$WG" 19082 "SNARE honeypot"
probe "$WG" 19081 "HTTP decoy"
probe "$WG" 18083 "API/cloud decoy" "/v2/_catalog"

info "[VPS-local auth service on Docker's proxy network]"
# auth-portal is an optional add-on (https://github.com/Xore/auth-backend),
# not part of this repo's own Compose stack — a missing container here is
# expected unless you've deployed it.
if docker inspect auth-portal >/dev/null 2>&1; then
  auth_state=$(docker inspect -f '{{.State.Status}}' auth-portal 2>/dev/null)
  auth_health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}not-configured{{end}}' auth-portal 2>/dev/null)
  if [[ "$auth_state" == "running" && "$auth_health" != "unhealthy" ]]; then
    pass "auth-portal is $auth_state (health: $auth_health)"
  else
    fail "auth-portal state: $auth_state (health: $auth_health)"
  fi
else
  info "auth-portal container not found — optional add-on not deployed (see Xore/auth-backend)"
fi

info "[Optional home application backends]"
optional_probe "$WG" 8080 "Static site"
optional_probe "$WG" 5000 "Flask API"
optional_probe "$WG" 5001 "Flask+Redis API"
optional_probe "$WG" 3000 "Node/VUI backend"
optional_probe "$WG" 3001 "Uptime Kuma"
optional_probe "$WG" 8070 "FileBrowser"
optional_probe "$WG" 4174 "SvelteKit blog"
optional_probe "$WG" 5002 "C# API"
optional_probe "$WG" 5003 "Go API"
optional_probe "$WG" 5004 "Rust API"
optional_probe "$WG" 8123 "Home Assistant upstream"

total=$((PASS + FAIL + WARN))
echo -e "\n${CYAN}Results:${NC} ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$WARN warnings${NC}, $total checks"
echo "A TCP-open backend that returns HTTP 5xx is unhealthy; inspect its container logs and Traefik service URL."
[[ $FAIL -eq 0 ]]
