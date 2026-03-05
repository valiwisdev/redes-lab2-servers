#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m';  GREEN='\033[0;32m';  YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m';   MAGENTA='\033[0;35m'
BOLD='\033[1m';    DIM='\033[2m';       NC='\033[0m'

ok()      { echo -e "  ${GREEN}[OK]${NC}    $*"; }
error()   { echo -e "  ${RED}[ERROR]${NC} $*"; }
info()    { echo -e "  ${CYAN}[INFO]${NC}  $*"; }
step()    { echo -e "\n  ${BOLD}▶ $*${NC}"; }
divider() { echo -e "  ${DIM}────────────────────────────────────────────────${NC}"; }

# ── Status checks ─────────────────────────────────────────────────────────────
check_ftp()   { docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'proftpd'; }
check_web()   { docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'nginx-web'; }
check_rtmp()  { docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'rtmp-nginx'; }

status_icon() {
    if $1 2>/dev/null; then echo -e "${GREEN}●${NC}"
    else echo -e "${RED}●${NC}"; fi
}

# ── Stop a service ────────────────────────────────────────────────────────────
stop_service() {
    local name="$1"
    local dir="$SCRIPT_DIR/$2"
    local check_fn="$3"

    if ! $check_fn 2>/dev/null; then
        info "$name is already stopped."
    else
        step "Stopping $name..."
        docker compose -f "$dir/docker-compose.yml" down --volumes \
            && ok "$name stopped." \
            || error "Failed to stop $name."
    fi
}

print_banner() {
    clear
    echo ""
    echo -e "  ${BOLD}${BLUE}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "  ${BOLD}${BLUE}║${NC}  ${BOLD}${CYAN}Service Manager${NC}                 ${BOLD}${BLUE}║${NC}"
    echo -e "  ${BOLD}${BLUE}║${NC}  ${DIM}REDES Y SERVICIOS DE COMUNICACIONES${NC}            ${BOLD}${BLUE}║${NC}"
    echo -e "  ${BOLD}${BLUE}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_menu() {
    local f w r
    f=$(status_icon check_ftp)
    w=$(status_icon check_web)
    r=$(status_icon check_rtmp)

    echo -e "  ${BOLD}Select a service to stop:${NC}"
    echo ""
    divider
    echo -e "   ${BOLD}1)${NC}  ${f}  ${MAGENTA}FTP Server${NC}"
    echo -e "   ${BOLD}2)${NC}  ${w}  ${GREEN}Web Server${NC}"
    echo -e "   ${BOLD}3)${NC}  ${r}  ${RED}RTMP Server${NC}"
    divider
    echo -e "   ${BOLD}a)${NC}  Stop all running services"
    divider
    echo -e "   ${BOLD}q)${NC}  ${DIM}Quit${NC}"
    echo ""
}

[[ "$EUID" -ne 0 ]] && { error "Run as root:  sudo bash stop_all.sh"; exit 1; }

while true; do
    print_banner
    print_menu
    read -rp "  → Option: " choice
    echo ""

    case "$choice" in
        1) stop_service "FTP Server"  "ftp-server"   check_ftp  ;;
        2) stop_service "Web Server"  "nginx-server" check_web  ;;
        3) stop_service "RTMP Server" "rtmp-server"  check_rtmp ;;
        a)
            step "Stopping all services..."
            stop_service "FTP Server"  "ftp-server"   check_ftp
            stop_service "Web Server"  "nginx-server" check_web
            stop_service "RTMP Server" "rtmp-server"  check_rtmp
            ;;
        q|Q|quit|exit) echo -e "\n  ${DIM}Goodbye.${NC}\n"; exit 0 ;;
        *) echo -e "  ${YELLOW}[WARN]${NC}  Unknown option: '$choice'" ;;
    esac

    echo ""; divider
    read -rp "  Press Enter to continue..." _
done
