#!/bin/bash
# =============================================================================
#  setup_dns.sh — BIND9 interactivo con soporte de actualización de registros
#
#  MODOS:
#    sudo bash setup_dns.sh              → instalación guiada paso a paso
#    sudo bash setup_dns.sh --add        → agregar/actualizar un registro
#    sudo bash setup_dns.sh --list       → ver registros actuales
#    sudo bash setup_dns.sh --help       → mostrar ayuda
# =============================================================================

set -e

ZONE_DIR="/etc/bind"
STATE_FILE="/etc/bind/.dns_state"

# ── Colores ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

info()   { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()     { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()   { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
header() { echo -e "\n${BOLD}$*${NC}"; echo "────────────────────────────────────────"; }

# =============================================================================
#  HELPERS
# =============================================================================

validate_ip() {
    local ip=$1
    if [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        IFS='.' read -r -a parts <<< "$ip"
        for p in "${parts[@]}"; do
            [[ $p -le 255 ]] || return 1
        done
        return 0
    fi
    return 1
}

ask_ip() {
    local desc=$1 varname=$2 optional=${3:-false}
    while true; do
        if $optional; then
            read -rp "  IP para $desc (Enter para omitir): " val
            [[ -z "$val" ]] && { eval "$varname=''"; return; }
        else
            read -rp "  IP para $desc: " val
        fi
        if validate_ip "$val"; then
            eval "$varname='$val'"
            return
        fi
        warn "IP invalida: '$val'. Intenta de nuevo."
    done
}

ask_text() {
    local prompt=$1 varname=$2 default=$3
    read -rp "  $prompt${default:+ [${default}]}: " val
    val=${val:-$default}
    eval "$varname='$val'"
}

bump_serial() {
    local file=$1
    local today serial new_serial
    today=$(date +%Y%m%d)
    serial=$(grep -oP '\d{10}(?=\s*;\s*Serial)' "$file" | head -1)
    if [[ -z "$serial" ]]; then
        new_serial="${today}01"
    elif [[ "${serial:0:8}" == "$today" ]]; then
        local seq=$(( 10#${serial:8:2} + 1 ))
        new_serial="${today}$(printf '%02d' "$seq")"
    else
        new_serial="${today}01"
    fi
    sed -i "s/$serial/$new_serial/" "$file"
    info "Serial actualizado: $serial -> $new_serial"
}

write_forward_zone() {
    local domain=$1 ip_dns=$2 ip_web=$3 ip_ftp=$4
    local file="$ZONE_DIR/db.${domain}"
    {
        echo "; ============================================================"
        echo ";  Zona directa -- ${domain}"
        echo "; ============================================================"
        echo "\$TTL    604800"
        echo "@       IN  SOA     dns.${domain}. root.${domain}. ("
        echo "                    $(date +%Y%m%d)01  ; Serial"
        echo "                    604800      ; Refresh"
        echo "                    86400       ; Retry"
        echo "                    2419200     ; Expire"
        echo "                    604800 )    ; Negative Cache TTL"
        echo ""
        echo "; Name Servers"
        echo "@       IN  NS      dns.${domain}."
        echo ""
        echo "; Registros A"
        [[ -n "$ip_dns" ]] && echo "dns     IN  A       ${ip_dns}"
        [[ -n "$ip_web" ]] && echo "web     IN  A       ${ip_web}"
        [[ -n "$ip_ftp" ]] && echo "ftp     IN  A       ${ip_ftp}"
    } > "$file"
}

write_reverse_zone() {
    local domain=$1 network=$2 ip_dns=$3 ip_web=$4 ip_ftp=$5
    local file="$ZONE_DIR/db.${network}"
    local last_dns last_web last_ftp
    [[ -n "$ip_dns" ]] && last_dns=$(echo "$ip_dns" | cut -d'.' -f4)
    [[ -n "$ip_web" ]] && last_web=$(echo "$ip_web" | cut -d'.' -f4)
    [[ -n "$ip_ftp" ]] && last_ftp=$(echo "$ip_ftp" | cut -d'.' -f4)
    local reverse
    reverse=$(echo "$network" | awk -F'.' '{print $3"."$2"."$1}').in-addr.arpa
    {
        echo "; ============================================================"
        echo ";  Zona inversa -- ${reverse}"
        echo "; ============================================================"
        echo "\$TTL    604800"
        echo "@       IN  SOA     dns.${domain}. root.${domain}. ("
        echo "                    $(date +%Y%m%d)01  ; Serial"
        echo "                    604800      ; Refresh"
        echo "                    86400       ; Retry"
        echo "                    2419200     ; Expire"
        echo "                    604800 )    ; Negative Cache TTL"
        echo ""
        echo "; Name Servers"
        echo "@       IN  NS      dns.${domain}."
        echo ""
        echo "; Registros PTR"
        [[ -n "$last_dns" ]] && echo "${last_dns}     IN  PTR     dns.${domain}."
        [[ -n "$last_web" ]] && echo "${last_web}     IN  PTR     web.${domain}."
        [[ -n "$last_ftp" ]] && echo "${last_ftp}     IN  PTR     ftp.${domain}."
    } > "$file"
}

reload_bind() {
    named-checkconf
    systemctl reload named 2>/dev/null || systemctl restart named
    ok "BIND9 recargado."
}

# =============================================================================
#  MODO --list
# =============================================================================
cmd_list() {
    header "Registros DNS actuales"
    [[ ! -f "$STATE_FILE" ]] && error "No se encontro estado guardado. Ejecuta setup primero."
    source "$STATE_FILE"
    local fwd="$ZONE_DIR/db.${DOMAIN}"
    [[ ! -f "$fwd" ]] && error "Archivo de zona no encontrado: $fwd"
    echo ""
    echo -e "  ${BOLD}Dominio :${NC} $DOMAIN"
    echo -e "  ${BOLD}Red     :${NC} ${NETWORK}.0/24"
    echo ""
    echo -e "  ${BOLD}Registros A (zona directa):${NC}"
    grep -E "^\s*(dns|web|ftp)\s+IN\s+A" "$fwd" | while read -r line; do
        echo "    $line"
    done
    echo ""
    echo -e "  ${BOLD}Registros PTR (zona inversa):${NC}"
    grep -E "^\s*[0-9]+\s+IN\s+PTR" "$ZONE_DIR/db.${NETWORK}" 2>/dev/null | while read -r line; do
        echo "    $line"
    done
}

# =============================================================================
#  MODO --add
# =============================================================================
cmd_add() {
    header "Agregar / Actualizar registro DNS"
    [[ ! -f "$STATE_FILE" ]] && error "No se encontro estado guardado. Ejecuta setup primero."
    source "$STATE_FILE"

    local fwd="$ZONE_DIR/db.${DOMAIN}"
    local rev="$ZONE_DIR/db.${NETWORK}"

    echo ""
    echo "  Dominio activo : $DOMAIN"
    echo "  Red activa     : ${NETWORK}.0/24"
    echo ""
    echo "  Servicios disponibles: dns  web  ftp"
    ask_text "Que servicio quieres agregar/actualizar? (dns/web/ftp)" SERVICE

    SERVICE=$(echo "$SERVICE" | tr '[:upper:]' '[:lower:]')
    [[ ! "$SERVICE" =~ ^(dns|web|ftp)$ ]] && error "Servicio invalido. Usa: dns, web o ftp."

    ask_ip "${SERVICE}.${DOMAIN}" NEW_IP

    # Actualizar zona directa
    if grep -qE "^${SERVICE}\s+IN\s+A" "$fwd"; then
        warn "Registro '$SERVICE' ya existe. Actualizando..."
        sed -i "s|^${SERVICE}[[:space:]]\+IN[[:space:]]\+A.*|${SERVICE}     IN  A       ${NEW_IP}|" "$fwd"
    else
        info "Agregando nuevo registro '$SERVICE'..."
        echo "${SERVICE}     IN  A       ${NEW_IP}" >> "$fwd"
    fi

    # Actualizar zona inversa
    local last_octet fqdn
    last_octet=$(echo "$NEW_IP" | cut -d'.' -f4)
    fqdn="${SERVICE}.${DOMAIN}."

    if grep -qE "IN[[:space:]]+PTR[[:space:]]+${SERVICE}\." "$rev" 2>/dev/null; then
        warn "Registro PTR '$SERVICE' ya existe. Actualizando..."
        sed -i "s|^[0-9]\+[[:space:]]\+IN[[:space:]]\+PTR[[:space:]]\+${SERVICE}\..*|${last_octet}     IN  PTR     ${fqdn}|" "$rev"
    else
        info "Agregando nuevo registro PTR '$SERVICE'..."
        echo "${last_octet}     IN  PTR     ${fqdn}" >> "$rev"
    fi

    # Actualizar estado guardado
    sed -i "s|^IP_${SERVICE^^}=.*|IP_${SERVICE^^}=\"${NEW_IP}\"|" "$STATE_FILE"

    bump_serial "$fwd"
    bump_serial "$rev"

    local reverse_zone
    reverse_zone=$(echo "$NETWORK" | awk -F'.' '{print $3"."$2"."$1}').in-addr.arpa
    named-checkzone "$DOMAIN" "$fwd"
    named-checkzone "$reverse_zone" "$rev"
    reload_bind

    echo ""
    ok "Registro '${SERVICE} -> ${NEW_IP}' aplicado en $DOMAIN"
    echo ""
    echo "  Prueba: nslookup ${SERVICE}.${DOMAIN} ${IP_DNS}"
}

# =============================================================================
#  MODO --help
# =============================================================================
cmd_help() {
    echo ""
    echo -e "${BOLD}setup_dns.sh${NC} — Configurador interactivo de BIND9"
    echo ""
    echo "  Modos de uso:"
    echo "    sudo bash setup_dns.sh           Instalacion guiada completa"
    echo "    sudo bash setup_dns.sh --add      Agregar o actualizar un registro"
    echo "    sudo bash setup_dns.sh --list     Ver registros actuales"
    echo "    sudo bash setup_dns.sh --help     Mostrar esta ayuda"
    echo ""
}

# =============================================================================
#  MODO SETUP (instalación guiada)
# =============================================================================
cmd_setup() {
    header "Configuracion de BIND9 — Instalacion guiada"

    echo ""
    ask_text "Numero de grupo (X)" GRUPO
    ask_text "Seccion (Y)" SECCION

    DOMAIN="labredes${GRUPO}${SECCION}.com"
    info "Dominio: $DOMAIN"
    echo ""

    header "Ingresa las IPs de cada servicio"
    echo "  (WEB y FTP son opcionales — agregales despues con --add)"
    echo ""

    # Auto-detectar IP del servidor DNS (esta misma maquina)
    AUTO_IP=$(hostname -I | awk '{print $1}')
    info "IP detectada automaticamente para este servidor: ${BOLD}${AUTO_IP}${NC}"
    read -rp "  Usar $AUTO_IP como IP del servidor DNS? (S/n): " USE_AUTO
    if [[ ! "$USE_AUTO" =~ ^[nN]$ ]]; then
        IP_DNS="$AUTO_IP"
        ok "IP DNS: $IP_DNS"
    else
        ask_ip "dns.${DOMAIN} (servidor DNS) [OBLIGATORIO]" IP_DNS
    fi

    ask_ip  "web.${DOMAIN} (servidor Web)" IP_WEB true
    ask_ip  "ftp.${DOMAIN} (servidor FTP)" IP_FTP true

    [[ -z "$IP_DNS" ]] && error "La IP del servidor DNS es obligatoria."

    NETWORK=$(echo "$IP_DNS" | cut -d'.' -f1-3)
    REVERSE_ZONE=$(echo "$NETWORK" | awk -F'.' '{print $3"."$2"."$1}').in-addr.arpa
    ZONE_FILE_FWD="db.${DOMAIN}"
    ZONE_FILE_REV="db.${NETWORK}"

    header "Resumen"
    echo "  Dominio  : $DOMAIN"
    echo "  Red      : ${NETWORK}.0/24"
    echo "  IP DNS   : $IP_DNS"
    echo "  IP WEB   : ${IP_WEB:-[pendiente]}"
    echo "  IP FTP   : ${IP_FTP:-[pendiente]}"
    echo "  Zona inv : $REVERSE_ZONE"
    echo ""
    read -rp "  Continuar con la instalacion? (s/N): " CONFIRM
    [[ ! "$CONFIRM" =~ ^[sS]$ ]] && { warn "Instalacion cancelada."; exit 0; }

    header "1/6  Instalando BIND9"
    apt-get update -q
    apt-get install -y bind9 bind9utils bind9-doc dnsutils
    ok "BIND9 instalado."

    header "2/6  Forzando solo IPv4"
    if grep -q '^OPTIONS=' /etc/default/named 2>/dev/null; then
        sed -i 's/^OPTIONS=.*/OPTIONS="-u bind -4"/' /etc/default/named
    else
        echo 'OPTIONS="-u bind -4"' >> /etc/default/named
    fi
    ok "IPv6 deshabilitado en BIND9."

    header "3/6  Creando zona directa"
    write_forward_zone "$DOMAIN" "$IP_DNS" "$IP_WEB" "$IP_FTP"
    ok "Archivo: $ZONE_DIR/$ZONE_FILE_FWD"

    header "4/6  Creando zona inversa"
    write_reverse_zone "$DOMAIN" "$NETWORK" "$IP_DNS" "$IP_WEB" "$IP_FTP"
    ok "Archivo: $ZONE_DIR/$ZONE_FILE_REV"

    header "5/6  Registrando zonas en named.conf"
    sed -i "/zone \"${DOMAIN}\"/,/^};/d" /etc/bind/named.conf.local 2>/dev/null || true
    sed -i "/zone \"${REVERSE_ZONE}\"/,/^};/d" /etc/bind/named.conf.local 2>/dev/null || true
    {
        echo ""
        echo "// Zona directa"
        echo "zone \"${DOMAIN}\" {"
        echo "    type master;"
        echo "    file \"${ZONE_DIR}/${ZONE_FILE_FWD}\";"
        echo "};"
        echo ""
        echo "// Zona inversa"
        echo "zone \"${REVERSE_ZONE}\" {"
        echo "    type master;"
        echo "    file \"${ZONE_DIR}/${ZONE_FILE_REV}\";"
        echo "};"
    } >> /etc/bind/named.conf.local
    {
        echo "options {"
        echo "    directory \"/var/cache/bind\";"
        echo "    forwarders { 8.8.8.8; 8.8.4.4; };"
        echo "    dnssec-validation auto;"
        echo "    listen-on    { any; };"
        echo "    listen-on-v6 { none; };"
        echo "    allow-query  { any; };"
        echo "};"
    } > /etc/bind/named.conf.options
    ok "named.conf actualizado."

    header "6/6  Validando con named-checkzone"
    named-checkzone "$DOMAIN" "$ZONE_DIR/$ZONE_FILE_FWD"
    named-checkzone "$REVERSE_ZONE" "$ZONE_DIR/$ZONE_FILE_REV"
    named-checkconf
    ok "Validacion exitosa."

    systemctl restart named
    systemctl enable named

    # Guardar estado para --add y --list
    {
        echo "DOMAIN=\"${DOMAIN}\""
        echo "NETWORK=\"${NETWORK}\""
        echo "IP_DNS=\"${IP_DNS}\""
        echo "IP_WEB=\"${IP_WEB}\""
        echo "IP_FTP=\"${IP_FTP}\""
    } > "$STATE_FILE"

    echo ""
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo -e "${GREEN} BIND9 listo para: ${DOMAIN}${NC}"
    echo -e "${GREEN}════════════════════════════════════════${NC}"
    echo ""
    echo "  Pruebas rapidas (desde un cliente):"
    echo "    nslookup dns.${DOMAIN} ${IP_DNS}"
    [[ -n "$IP_WEB" ]] && echo "    nslookup web.${DOMAIN} ${IP_DNS}"
    [[ -n "$IP_FTP" ]] && echo "    nslookup ftp.${DOMAIN} ${IP_DNS}"
    echo ""
    if [[ -z "$IP_WEB" || -z "$IP_FTP" ]]; then
        echo "  Registros pendientes — agrega despues con:"
        echo "    sudo bash $0 --add"
        echo ""
    fi
    echo "  Ver registros actuales:"
    echo "    sudo bash $0 --list"
    echo ""
}

# =============================================================================
#  ENTRY POINT
# =============================================================================
[[ "$EUID" -ne 0 ]] && error "Ejecuta como root: sudo bash $0"

case "${1:-}" in
    --add)   cmd_add   ;;
    --list)  cmd_list  ;;
    --help)  cmd_help  ;;
    "")      cmd_setup ;;
    *)       warn "Opcion desconocida: $1"; cmd_help ;;
esac