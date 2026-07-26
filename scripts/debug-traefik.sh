#!/usr/bin/env bash
# Diagnose the current Traefik routes from the VPS.
# Architecture: Internet -> VPS Traefik -> Docker proxy service -> 10.8.0.2.
# Usage: ./debug-traefik.sh [DOMAIN]

DOMAIN="${1:-xore.rocks}"
WG_HOME="${HOME_WG_IP:-10.8.0.2}"
TRAEFIK_API="${TRAEFIK_API:-http://127.0.0.1:8080}"
PASS=0; FAIL=0; WARN=0
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; CYAN='\033[0;36m'; NC='\033[0m'

pass() { echo -e "  ${GREEN}[PASS]${NC} $*"; ((PASS++)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $*"; ((FAIL++)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $*"; ((WARN++)); }
info() { echo -e "\n${CYAN}$*${NC}"; }
tcp_open() { timeout 3 bash -c "</dev/tcp/$1/$2" 2>/dev/null; }

# label|hostname prefix ("@" means apex)|home port ("docker" means VPS-local)
VHOSTS=(
  "Apex/static|@|8080"
  "WWW/static|www|8080"
  "Static alias|static|8080"
  "Auth portal|auth|docker"
  "Uptime Kuma|status|3001"
  "HTTP decoy|decoy|19081"
  "SNARE portal|www-portal|19082"
  "SNARE alias|snare|19082"
  "Honeypot dashboard|honeypot|19090"
  "Dashboard alias|dashboard|19090"
  "Kibana|kibana|19601"
  "Tanner|tanner|19091"
  "EveBox|evebox|19636"
  "Arkime|arkime|19080"
  "Home Assistant|ha|8123"
)

echo -e "${CYAN}Traefik route diagnostic - domain: $DOMAIN - home: $WG_HOME${NC}"

info "[WireGuard]"
if ping -c1 -W2 "$WG_HOME" >/dev/null 2>&1; then
  pass "$WG_HOME is reachable"
  wg_ok=1
else
  fail "$WG_HOME is unreachable"
  wg_ok=0
fi

info "[Traefik API]"
if traefik_data=$(curl -sf --max-time 5 "$TRAEFIK_API/api/rawdata" 2>/dev/null); then
  pass "Traefik API is reachable at $TRAEFIK_API"
else
  warn "Traefik API is disabled or unavailable; router-definition checks will be skipped"
  traefik_data=""
fi

info "[Routes]"
for entry in "${VHOSTS[@]}"; do
  IFS='|' read -r label prefix backend <<<"$entry"
  if [[ "$prefix" == "@" ]]; then host="$DOMAIN"; else host="$prefix.$DOMAIN"; fi
  echo "  $host ($label)"

  if [[ -n "$traefik_data" ]]; then
    if grep -Fqi "$host" <<<"$traefik_data"; then
      pass "router is defined"
    else
      fail "router is missing"
    fi
  fi

  if [[ "$backend" == "docker" ]]; then
    # auth-portal is an optional add-on (https://github.com/Xore/auth-backend),
    # not deployed by this repo's own Compose stack.
    if docker inspect auth-portal >/dev/null 2>&1; then
      state=$(docker inspect -f '{{.State.Status}}' auth-portal 2>/dev/null)
      health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}not-configured{{end}}' auth-portal 2>/dev/null)
      if [[ "$state" == "running" && "$health" != "unhealthy" ]]; then
        pass "VPS-local auth-portal is $state (health: $health)"
      else
        fail "VPS-local auth-portal is $state (health: $health)"
      fi
    else
      info "auth-portal container not found — optional add-on not deployed (see Xore/auth-backend)"
    fi
  elif [[ $wg_ok -eq 1 ]]; then
    if tcp_open "$WG_HOME" "$backend"; then
      pass "home backend $WG_HOME:$backend is open"
    else
      fail "home backend $WG_HOME:$backend is closed"
    fi
  fi

  code=$(curl -sk --max-time 8 -o /dev/null -w '%{http_code}' --resolve "$host:443:127.0.0.1" "https://$host/" 2>/dev/null)
  case "$code" in
    2??|3??|401|403) pass "end-to-end HTTPS returned $code" ;;
    404)             warn "end-to-end HTTPS returned 404 (route answered)" ;;
    421)             fail "end-to-end HTTPS returned 421 (router/SNI mismatch)" ;;
    502|503|504)     fail "end-to-end HTTPS returned $code (backend failure)" ;;
    000|'')          fail "end-to-end HTTPS did not answer" ;;
    *)               warn "end-to-end HTTPS returned $code" ;;
  esac
done

total=$((PASS + FAIL + WARN))
echo -e "\n${CYAN}Results:${NC} ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}, ${YELLOW}$WARN warnings${NC}, $total checks"
echo "421 indicates routing/SNI trouble; 502-504 indicates a router whose backend is unavailable."
[[ $FAIL -eq 0 ]]
