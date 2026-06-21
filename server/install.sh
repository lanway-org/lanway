#!/usr/bin/env bash
#
# Lanway server installer.
#
#   bash <(curl -fsSL https://get.lanway.org)
#
# Optional environment variables:
#   LANWAY_DOMAIN   set to enable own-domain TLS mode (Let's Encrypt)
#   LANWAY_PORT     management API port (default 8080)
#
set -euo pipefail

TEAL='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BOLD='\033[1m'; NC='\033[0m'
INSTALL_DIR="/opt/lanway"
COMPOSE_FILE="${INSTALL_DIR}/docker-compose.yml"
IMAGE="ghcr.io/lanway-org/lanway-server:latest"
API_PORT="${LANWAY_PORT:-8080}"

# Stealth mode: reality (default, owns 443) | tls (own domain, owns 443) |
# proxy (sit behind an existing nginx/site that already owns 443).
MODE="${LANWAY_MODE:-reality}"
WS_PORT="${LANWAY_VPN_PORT:-8444}"   # local port nginx forwards to, proxy mode
WS_PATH="${LANWAY_WS_PATH:-}"        # secret WebSocket path, proxy mode

say()  { echo -e "${TEAL}▸${NC} $*"; }
ok()   { echo -e "${GREEN}✓${NC} $*"; }
warn() { echo -e "${YELLOW}!${NC} $*"; }
die()  { echo -e "${RED}✗${NC} $*" >&2; exit 1; }

banner() {
  echo -e "${TEAL}${BOLD}"
  cat <<'EOF'
   _
  | |    __ _ _ ____      ____ _ _   _
  | |   / _` | '_ \ \ /\ / / _` | | | |
  | |__| (_| | | | \ V  V / (_| | |_| |
  |_____\__,_|_| |_|\_/\_/ \__,_|\__, |
                                  |___/
  Free to use. Free to speak. Unlimited.
EOF
  echo -e "${NC}"
}

require_root() {
  [ "$(id -u)" -eq 0 ] || die "Please run as root (try: sudo bash <(curl -fsSL https://get.lanway.org))"
}

detect_public_ip() {
  local ip
  ip="$(curl -fsSL --max-time 8 https://api.ipify.org 2>/dev/null || true)"
  [ -z "$ip" ] && ip="$(curl -fsSL --max-time 8 https://ifconfig.me 2>/dev/null || true)"
  [ -z "$ip" ] && ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  echo "$ip"
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    ok "Docker already installed"
  else
    say "Installing Docker…"
    curl -fsSL https://get.docker.com | sh >/dev/null 2>&1 || die "Docker installation failed"
    systemctl enable --now docker >/dev/null 2>&1 || true
    ok "Docker installed"
  fi
  docker compose version >/dev/null 2>&1 || die "Docker Compose plugin is required but missing"
}

open_firewall() {
  command -v ufw >/dev/null 2>&1 || return 0
  # In proxy mode the existing site already owns 443 — don't touch it.
  [ "$MODE" != "proxy" ] && ufw allow 443/tcp >/dev/null 2>&1 || true
  ufw allow "${API_PORT}"/tcp >/dev/null 2>&1 || true
  ok "Firewall rules added (${MODE} mode)"
}

write_compose() {
  mkdir -p "$INSTALL_DIR"
  local pub_host="$1"

  # Port mapping and mode environment differ for proxy mode.
  local ports env_lines
  if [ "$MODE" = "proxy" ]; then
    ports="      - \"127.0.0.1:${WS_PORT}:${WS_PORT}\"
      - \"${API_PORT}:8080\""
    env_lines="      - LANWAY_MODE=proxy
      - LANWAY_DOMAIN=${pub_host}
      - LANWAY_WS_PATH=${WS_PATH}
      - LANWAY_VPN_PORT=${WS_PORT}
      - LANWAY_PUBLIC_PORT=443"
  else
    ports="      - \"443:443\"
      - \"${API_PORT}:8080\""
    env_lines="      - LANWAY_PUBLIC_HOST=${pub_host}"
    [ "$MODE" = "tls" ] && env_lines="${env_lines}
      - LANWAY_MODE=tls
      - LANWAY_DOMAIN=${pub_host}"
  fi
  [ -n "${LANWAY_API_KEY:-}" ] && env_lines="${env_lines}
      - LANWAY_API_KEY=${LANWAY_API_KEY}"

  cat > "$COMPOSE_FILE" <<EOF
services:
  lanway:
    image: ${IMAGE}
    container_name: lanway
    restart: always
    ports:
${ports}
    volumes:
      - ${INSTALL_DIR}:/config
    environment:
${env_lines}
EOF
  ok "Wrote ${COMPOSE_FILE}"
}

print_nginx_snippet() {
  local domain="$1"
  echo
  echo -e "${YELLOW}${BOLD}  One more step — add this to your nginx server block for ${domain}:${NC}"
  echo
  cat <<EOF
    # Lanway tunnel (looks like a normal sub-path of your site)
    location ${WS_PATH} {
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_pass http://127.0.0.1:${WS_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_read_timeout 300s;
    }
EOF
  echo
  echo -e "  Then reload nginx:  ${TEAL}nginx -t && systemctl reload nginx${NC}"
}

wait_for_health() {
  say "Waiting for the server to become healthy…"
  for _ in $(seq 1 30); do
    if curl -fsSk "https://127.0.0.1:${API_PORT}/api/health" >/dev/null 2>&1; then
      ok "Server is healthy"
      return 0
    fi
    sleep 2
  done
  warn "Server did not report healthy in time; check: docker logs lanway"
  return 1
}

read_access_key() {
  # The server persists its config on first boot; read the generated key.
  for _ in $(seq 1 15); do
    if [ -f "${INSTALL_DIR}/lanway.json" ]; then
      grep -o '"api_key": *"[^"]*"' "${INSTALL_DIR}/lanway.json" | head -1 | sed 's/.*"api_key": *"//;s/"//'
      return 0
    fi
    sleep 1
  done
  echo ""
}

main() {
  banner
  require_root
  install_docker
  open_firewall

  local pub_host
  if [ "$MODE" = "proxy" ]; then
    [ -z "${LANWAY_DOMAIN:-}" ] && die "Proxy mode needs your site's domain: set LANWAY_DOMAIN=yourdomain.com"
    pub_host="$LANWAY_DOMAIN"
    # Generate a hard-to-guess WebSocket path if the operator didn't pick one.
    [ -z "$WS_PATH" ] && WS_PATH="/$(head -c 9 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 12)"
    [ "${WS_PATH:0:1}" != "/" ] && WS_PATH="/${WS_PATH}"
    say "Proxy mode behind existing site: ${pub_host}, path ${WS_PATH}"
  elif [ -n "${LANWAY_DOMAIN:-}" ]; then
    MODE="tls"
    pub_host="$LANWAY_DOMAIN"
    say "TLS (own-domain) mode: ${pub_host}"
  else
    pub_host="$(detect_public_ip)"
    [ -z "$pub_host" ] && die "Could not detect this server's public IP; set LANWAY_DOMAIN or LANWAY_PUBLIC_HOST"
    say "REALITY mode on public address: ${pub_host}"
  fi

  write_compose "$pub_host"

  say "Pulling and starting Lanway…"
  ( cd "$INSTALL_DIR" && docker compose pull -q && docker compose up -d ) || die "Failed to start container"

  wait_for_health || true
  local key; key="$(read_access_key)"

  echo
  echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════${NC}"
  echo -e "${GREEN}${BOLD}  Lanway is running.${NC}"
  echo
  echo -e "  ${BOLD}Manager API URL${NC} :  https://${pub_host}:${API_PORT}"
  if [ -n "$key" ]; then
    echo -e "  ${BOLD}Access key${NC}      :  ${key}"
  else
    echo -e "  ${BOLD}Access key${NC}      :  (run: cat ${INSTALL_DIR}/lanway.json)"
  fi
  echo
  echo -e "  Open the ${TEAL}Lanway Manager${NC} app and paste the URL and key above."
  echo -e "${GREEN}${BOLD}════════════════════════════════════════════════════════════${NC}"

  [ "$MODE" = "proxy" ] && print_nginx_snippet "$pub_host"
}

main "$@"
