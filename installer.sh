#!/bin/bash
# =============================================================================
#  installer.sh — Interactive installer for all services
#
#  Usage:
#    sudo bash installer.sh
# =============================================================================

set -e

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m';  GREEN='\033[0;32m';  YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BLUE='\033[0;34m';   MAGENTA='\033[0;35m'
BOLD='\033[1m';    DIM='\033[2m';       NC='\033[0m'

info()    { echo -e "  ${CYAN}[INFO]${NC}  $*"; }
ok()      { echo -e "  ${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "  ${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "  ${RED}[ERROR]${NC} $*"; }
step()    { echo -e "\n  ${BOLD}${BLUE}▶ $*${NC}"; }
divider() { echo -e "  ${DIM}────────────────────────────────────────────────${NC}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Status checks ─────────────────────────────────────────────────────────────
check_docker()    { command -v docker &>/dev/null && docker info &>/dev/null 2>&1; }
check_ftp()       { docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'proftpd'; }
check_nginx_web() { docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'nginx-web'; }
check_rtmp()      { docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'rtmp-nginx'; }
check_dns()       { systemctl is-active --quiet named 2>/dev/null; }

status_icon() {
    if $1 2>/dev/null; then echo -e "${GREEN}●${NC}"
    else echo -e "${DIM}○${NC}"; fi
}

# =============================================================================
#  BANNER
# =============================================================================
print_banner() {
    clear
    echo ""
    echo -e "  ${BOLD}${BLUE}╔══════════════════════════════════════════════════╗${NC}"
    echo -e "  ${BOLD}${BLUE}║${NC}  ${BOLD}${CYAN}Service Installer${NC}               ${BOLD}${BLUE}║${NC}"
    echo -e "  ${BOLD}${BLUE}║${NC}  ${DIM}REDES Y SERVICIOS DE COMUNICACIONES${NC}            ${BOLD}${BLUE}║${NC}"
    echo -e "  ${BOLD}${BLUE}╚══════════════════════════════════════════════════╝${NC}"
    echo ""
}

# =============================================================================
#  MAIN MENU
# =============================================================================
print_menu() {
    local d f w r n
    d=$(status_icon check_docker)
    f=$(status_icon check_ftp)
    w=$(status_icon check_nginx_web)
    r=$(status_icon check_rtmp)
    n=$(status_icon check_dns)

    echo -e "  ${BOLD}Select a service to configure:${NC}"
    echo ""
    divider
    echo -e "   ${BOLD}1)${NC}  ${d}  ${CYAN}Docker${NC}                   ${DIM}required for 2, 3, 4${NC}"
    divider
    echo -e "   ${BOLD}2)${NC}  ${f}  ${MAGENTA}FTP Server${NC}               ${DIM}ProFTPD · ports 21, 30000-30009${NC}"
    echo -e "   ${BOLD}3)${NC}  ${w}  ${GREEN}Web Server${NC}               ${DIM}Nginx · ports 80, 443 (SSL)${NC}"
    echo -e "   ${BOLD}4)${NC}  ${r}  ${RED}RTMP Server${NC}              ${DIM}Nginx-RTMP + ffmpeg · 80, 1935${NC}"
    divider
    echo -e "   ${BOLD}5)${NC}  ${n}  ${BLUE}DNS Server${NC}               ${DIM}BIND9 · no Docker needed${NC}"
    divider
    echo -e "   ${BOLD}q)${NC}  ${DIM}Quit${NC}"
    echo ""
}

# =============================================================================
#  HELPERS
# =============================================================================
require_script() {
    [[ -f "$1" ]] || { error "Script not found: $1\n  Run installer.sh from the repo root."; exit 1; }
}

# ── Docker gate: used at the start of any service that needs it ───────────────
require_docker() {
    if ! check_docker; then
        echo ""
        error "Docker is not installed. Go to option 1 from the main menu to install it first."
        echo ""
        read -rp "  Press Enter to return to menu..." _
        return 1
    fi
}

# ── Static IP: last option in every service submenu ───────────────────────────
submenu_static_ip() {
    local iface ip_now
    iface=$(ip -o -4 route show to default | awk '{print $5}' | head -1)
    ip_now=$(ip -o -4 addr show "$iface" | awk '{print $4}' | cut -d'/' -f1 | head -1)

    echo ""
    echo -e "  ${DIM}Interface: ${iface}  |  Current IP: ${ip_now}${NC}"
    echo ""
    read -rp "  Configure static IP for this server? (s/N): " ans
    if [[ "$ans" =~ ^[sS]$ ]]; then
        require_script "$SCRIPT_DIR/extras/set_static_ip.sh"
        bash "$SCRIPT_DIR/extras/set_static_ip.sh"
        ok "Static IP configured."
    else
        info "Skipping — keeping current IP (${ip_now})."
    fi
}

# ── Service banner ─────────────────────────────────────────────────────────────
service_header() {
    print_banner
    echo -e "  ${BOLD}$1 $2${NC}"
    echo -e "  ${DIM}$3${NC}"
    echo ""
    divider
    echo ""
}

# =============================================================================
#  1 — DOCKER
# =============================================================================
run_install_docker() {
    service_header "🐳" "Docker" "Docker CE + Compose plugin from the official repository"

    if check_docker; then
        ok "Docker is already installed: $(docker --version)"
        echo ""
        info "Nothing to do — returning to main menu."
        sleep 2
        return
    fi

    require_script "$SCRIPT_DIR/extras/install_docker.sh"
    bash "$SCRIPT_DIR/extras/install_docker.sh"
    echo ""
    ok "Docker installed."
    warn "Run 'newgrp docker' or log out/in for group changes to take effect."
}

# =============================================================================
#  2 — FTP
# =============================================================================
run_ftp() {
    while true; do
        service_header "📁" "FTP Server — ProFTPD" "ProFTPD in Docker · passive mode · ports 21, 30000-30009"

        if check_docker; then echo -e "  ${DIM}${GREEN}Docker: running${NC}"
        else echo -e "  ${DIM}${RED}Docker: not installed — install it from option 1${NC}"; fi
        echo ""
        echo -e "   ${BOLD}a)${NC}  Configure and start ProFTPD"
        echo -e "   ${BOLD}b)${NC}  Show logs / status"
        echo -e "   ${BOLD}c)${NC}  Set static IP for this server"
        echo -e "   ${BOLD}q)${NC}  Back to main menu"
        echo ""
        read -rp "  → Option: " opt

        case "$opt" in
            a)
                require_docker || return
                require_script "$SCRIPT_DIR/ftp-server/setup_ftp.sh"
                cd "$SCRIPT_DIR/ftp-server"
                bash setup_ftp.sh
                cd "$SCRIPT_DIR"
                ;;
            b)
                step "FTP Server status"
                docker ps --filter name=proftpd \
                    --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null \
                    || warn "Container not running."
                echo ""
                info "Full logs: cd ftp-server && docker compose logs proftpd"
                ;;
            c) submenu_static_ip ;;
            q|Q|"") return ;;
            *) warn "Unknown option: '$opt'" ;;
        esac

        echo ""; divider
        read -rp "  Press Enter to continue..." _
    done
}

# =============================================================================
#  3 — NGINX WEB
# =============================================================================
run_nginx_web() {
    local nginx_dir="$SCRIPT_DIR/nginx-server"

    while true; do
        service_header "🌐" "Web Server — Nginx + SSL" "nginx:alpine in Docker · HTTP port 80 · HTTPS port 443 · self-signed cert"

        if check_docker; then echo -e "  ${DIM}${GREEN}Docker: running${NC}"
        else echo -e "  ${DIM}${RED}Docker: not installed — install it from option 1${NC}"; fi
        if [[ -f "$nginx_dir/certs/server.crt" ]]; then echo -e "  ${DIM}${GREEN}Certificate: found${NC}"
        else echo -e "  ${DIM}${YELLOW}Certificate: missing — will be generated on step a${NC}"; fi
        echo ""
        echo -e "   ${BOLD}a)${NC}  Generate certificate and start Nginx"
        echo -e "   ${BOLD}b)${NC}  Show logs / status"
        echo -e "   ${BOLD}c)${NC}  Set static IP for this server"
        echo -e "   ${BOLD}q)${NC}  Back to main menu"
        echo ""
        read -rp "  → Option: " opt

        case "$opt" in
            a)
                require_docker || return
                require_script "$nginx_dir/gen_certs.sh"
                require_script "$nginx_dir/docker-compose.yml"
                if [[ -f "$nginx_dir/certs/server.crt" ]]; then
                    ok "Certificate already exists."
                    read -rp "  Regenerate? (s/N): " ans
                    if [[ "$ans" =~ ^[sS]$ ]]; then
                        step "Regenerating SSL certificate..."
                        bash "$nginx_dir/gen_certs.sh"
                    fi
                else
                    step "Generating SSL certificate..."
                    bash "$nginx_dir/gen_certs.sh"
                fi
                step "Starting Nginx..."
                cd "$nginx_dir" && docker compose up -d && cd "$SCRIPT_DIR"
                local ip; ip=$(hostname -I | awk '{print $1}')
                echo ""
                ok "Nginx running."
                info "HTTP  → http://$ip"
                info "HTTPS → https://$ip  (curl -k https://$ip)"
                ;;
            b)
                step "Web Server status"
                docker ps --filter name=nginx-web \
                    --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null \
                    || warn "Container not running."
                echo ""
                info "Full logs: cd nginx-server && docker compose logs nginx"
                ;;
            c) submenu_static_ip ;;
            q|Q|"") return ;;
            *) warn "Unknown option: '$opt'" ;;
        esac

        echo ""; divider
        read -rp "  Press Enter to continue..." _
    done
}

# =============================================================================
#  4 — RTMP
# =============================================================================
run_rtmp() {
    local rtmp_dir="$SCRIPT_DIR/rtmp-server"
    local env_file="$rtmp_dir/.env"

    while true; do
        service_header "📡" "RTMP Server — Nginx-RTMP + ffmpeg" "rtmp-nginx (port 1935) + ffmpeg-publisher (loops video)"

        local sk vf
        sk=$(grep '^STREAM_KEY=' "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "1")
        vf=$(grep '^VIDEO_FILE='  "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "IVE.mp4")

        if check_docker; then echo -e "  ${DIM}${GREEN}Docker: running${NC}"
        else echo -e "  ${DIM}${RED}Docker: not installed — install it from option 1${NC}"; fi
        echo -e "  ${DIM}Stream key: ${sk}  |  Video file: ${vf}${NC}"
        echo ""
        echo -e "   ${BOLD}a)${NC}  Configure stream key / video file and start RTMP"
        echo -e "   ${BOLD}b)${NC}  Show logs / status"
        echo -e "   ${BOLD}c)${NC}  Set static IP for this server"
        echo -e "   ${BOLD}q)${NC}  Back to main menu"
        echo ""
        read -rp "  → Option: " opt

        case "$opt" in
            a)
                require_docker || return
                require_script "$rtmp_dir/docker-compose.yml"
                echo ""
                read -rp "  Stream key  [${sk}]: " new_sk; new_sk="${new_sk:-$sk}"
                read -rp "  Video file  [${vf}]: " new_vf; new_vf="${new_vf:-$vf}"
                [[ ! -f "$rtmp_dir/videos/$new_vf" ]] && \
                    warn "Video not found in rtmp-server/videos/ — place it there before starting."
                printf 'STREAM_KEY=%s\nVIDEO_FILE=%s\n' "$new_sk" "$new_vf" > "$env_file"
                ok ".env saved."
                step "Starting RTMP containers..."
                cd "$rtmp_dir" && docker compose up -d --build && cd "$SCRIPT_DIR"
                local ip; ip=$(hostname -I | awk '{print $1}')
                sk=$(grep '^STREAM_KEY=' "$env_file" 2>/dev/null | cut -d'=' -f2 || echo "1")
                echo ""
                ok "RTMP server running."
                info "Stream  → rtmp://$ip/live/$sk"
                info "Health  → http://$ip"
                ;;
            b)
                step "RTMP Server status"
                docker ps --filter name=rtmp-nginx --filter name=ffmpeg-publisher \
                    --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null \
                    || warn "Containers not running."
                echo ""
                info "Full logs: cd rtmp-server && docker compose logs -f"
                ;;
            c) submenu_static_ip ;;
            q|Q|"") return ;;
            *) warn "Unknown option: '$opt'" ;;
        esac

        echo ""; divider
        read -rp "  Press Enter to continue..." _
    done
}

# =============================================================================
#  5 — DNS
# =============================================================================
run_dns() {
    local script="$SCRIPT_DIR/dns-server/setup_dns.sh"

    while true; do
        service_header "🌍" "DNS Server — BIND9" "BIND9 installed directly on the VM · zones for labredesXY.com"

        if command -v named &>/dev/null; then echo -e "  ${DIM}${GREEN}BIND9: $(named -v 2>&1 | head -1)${NC}"
        else echo -e "  ${DIM}${YELLOW}BIND9: not installed — run option a first${NC}"; fi
        echo ""
        echo -e "   ${BOLD}a)${NC}  Install BIND9"
        echo -e "   ${BOLD}b)${NC}  Full DNS setup       ${DIM}(first time, interactive)${NC}"
        echo -e "   ${BOLD}c)${NC}  Add / update record  ${DIM}(--add)${NC}"
        echo -e "   ${BOLD}d)${NC}  List current records ${DIM}(--list)${NC}"
        echo -e "   ${BOLD}e)${NC}  Set static IP for this server"
        echo -e "   ${BOLD}q)${NC}  Back to main menu"
        echo ""
        read -rp "  → Option: " opt

        case "$opt" in
            a)
                if command -v named &>/dev/null; then
                    ok "BIND9 already installed: $(named -v 2>&1 | head -1)"
                else
                    step "Installing BIND9..."
                    apt-get update -qq
                    apt-get install -y bind9 bind9utils bind9-doc dnsutils
                    ok "BIND9 installed."
                fi
                ;;
            b) require_script "$script"; bash "$script"        ;;
            c) require_script "$script"; bash "$script" --add  ;;
            d) require_script "$script"; bash "$script" --list ;;
            e) submenu_static_ip ;;
            q|Q|"") return ;;
            *) warn "Unknown option: '$opt'" ;;
        esac

        echo ""; divider
        read -rp "  Press Enter to continue..." _
    done
}

# =============================================================================
#  ENTRY POINT
# =============================================================================
[[ "$EUID" -ne 0 ]] && { error "Run as root:  sudo bash installer.sh"; exit 1; }

while true; do
    print_banner
    print_menu
    read -rp "  → Option: " choice
    echo ""

    case "$choice" in
        1) run_install_docker ;;
        2) run_ftp            ;;
        3) run_nginx_web      ;;
        4) run_rtmp           ;;
        5) run_dns            ;;
        q|Q|quit|exit) echo -e "\n  ${DIM}Goodbye.${NC}\n"; exit 0 ;;
        *) warn "Unknown option: '$choice'" ;;
    esac

    echo ""; divider
    read -rp "  Press Enter to return to menu..." _
done