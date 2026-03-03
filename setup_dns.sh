#!/bin/bash
# =============================================================================
#  setup_dns.sh — Configura BIND9 con zonas directa e inversa
#  Uso: sudo bash setup_dns.sh <GRUPO> <SECCION> <IP_DNS> <IP_WEB> <IP_FTP>
#
#  Ejemplo:
#    sudo bash setup_dns.sh 3 1 192.168.10.10 192.168.10.20 192.168.10.30
# =============================================================================

set -e

# ── 0. Validar argumentos ─────────────────────────────────────────────────────
if [ "$#" -ne 5 ]; then
    echo "Uso: sudo bash $0 <GRUPO> <SECCION> <IP_DNS> <IP_WEB> <IP_FTP>"
    echo "  Ejemplo: sudo bash $0 3 1 192.168.10.10 192.168.10.20 192.168.10.30"
    exit 1
fi

GRUPO=$1
SECCION=$2
IP_DNS=$3
IP_WEB=$4
IP_FTP=$5

DOMAIN="labredes${GRUPO}${SECCION}.com"

# Extraer la red (primeros 3 octetos) y ultimos octetos
NETWORK=$(echo "$IP_DNS" | cut -d'.' -f1-3)
LAST_DNS=$(echo "$IP_DNS" | cut -d'.' -f4)
LAST_WEB=$(echo "$IP_WEB" | cut -d'.' -f4)
LAST_FTP=$(echo "$IP_FTP" | cut -d'.' -f4)

# Red inversa para zona PTR  (ej: 10.168.192.in-addr.arpa)
REVERSE_ZONE=$(echo "$NETWORK" | awk -F'.' '{print $3"."$2"."$1}').in-addr.arpa

ZONE_DIR="/etc/bind"
ZONE_FILE_FWD="db.${DOMAIN}"
ZONE_FILE_REV="db.${NETWORK}"

echo "============================================================"
echo " Dominio  : $DOMAIN"
echo " Red      : ${NETWORK}.0/24"
echo " IP DNS   : $IP_DNS"
echo " IP WEB   : $IP_WEB"
echo " IP FTP   : $IP_FTP"
echo " Zona inv : $REVERSE_ZONE"
echo "============================================================"

# ── 1. Instalar BIND9 ─────────────────────────────────────────────────────────
echo "[1/6] Instalando BIND9..."
apt-get update -q
apt-get install -y bind9 bind9utils bind9-doc dnsutils

# ── 2. Forzar solo IPv4 ───────────────────────────────────────────────────────
echo "[2/6] Configurando BIND9 para IPv4 unicamente..."
if grep -q '^OPTIONS=' /etc/default/named 2>/dev/null; then
    sed -i 's/^OPTIONS=.*/OPTIONS="-u bind -4"/' /etc/default/named
else
    echo 'OPTIONS="-u bind -4"' >> /etc/default/named
fi

# ── 3. Zona directa ──────────────────────────────────────────────────────────
echo "[3/6] Creando zona directa: ${ZONE_DIR}/${ZONE_FILE_FWD}"
cat > "${ZONE_DIR}/${ZONE_FILE_FWD}" << ZONE_FWD
; ============================================================
;  Zona directa -- ${DOMAIN}
; ============================================================
\$TTL    604800
@       IN  SOA     dns.${DOMAIN}. root.${DOMAIN}. (
                    2024010101  ; Serial  (AAAMMDDnn)
                    604800      ; Refresh
                    86400       ; Retry
                    2419200     ; Expire
                    604800 )    ; Negative Cache TTL

; Name Servers
@       IN  NS      dns.${DOMAIN}.

; Registros A
dns     IN  A       ${IP_DNS}
web     IN  A       ${IP_WEB}
ftp     IN  A       ${IP_FTP}
ZONE_FWD

# ── 4. Zona inversa ──────────────────────────────────────────────────────────
echo "[4/6] Creando zona inversa: ${ZONE_DIR}/${ZONE_FILE_REV}"
cat > "${ZONE_DIR}/${ZONE_FILE_REV}" << ZONE_REV
; ============================================================
;  Zona inversa -- ${REVERSE_ZONE}
; ============================================================
\$TTL    604800
@       IN  SOA     dns.${DOMAIN}. root.${DOMAIN}. (
                    2024010101  ; Serial
                    604800      ; Refresh
                    86400       ; Retry
                    2419200     ; Expire
                    604800 )    ; Negative Cache TTL

; Name Servers
@       IN  NS      dns.${DOMAIN}.

; Registros PTR
${LAST_DNS}     IN  PTR     dns.${DOMAIN}.
${LAST_WEB}     IN  PTR     web.${DOMAIN}.
${LAST_FTP}     IN  PTR     ftp.${DOMAIN}.
ZONE_REV

# ── 5. named.conf.local ───────────────────────────────────────────────────────
echo "[5/6] Registrando zonas en named.conf.local..."
# Limpiar entradas previas (idempotente)
python3 - <<PYEOF
import re, sys
with open('/etc/bind/named.conf.local','r') as f:
    content = f.read()
# Eliminar bloques zone ya existentes para estos dominios
for z in ['${DOMAIN}','${REVERSE_ZONE}']:
    content = re.sub(r'// ?.*\n?zone "' + re.escape(z) + r'"[^}]+\};\n?', '', content)
with open('/etc/bind/named.conf.local','w') as f:
    f.write(content)
PYEOF

cat >> /etc/bind/named.conf.local << CONF_LOCAL

// Zona directa
zone "${DOMAIN}" {
    type master;
    file "${ZONE_DIR}/${ZONE_FILE_FWD}";
};

// Zona inversa
zone "${REVERSE_ZONE}" {
    type master;
    file "${ZONE_DIR}/${ZONE_FILE_REV}";
};
CONF_LOCAL

# ── named.conf.options (solo IPv4) ────────────────────────────────────────────
cat > /etc/bind/named.conf.options << CONF_OPT
options {
    directory "/var/cache/bind";

    forwarders {
        8.8.8.8;
        8.8.4.4;
    };

    dnssec-validation auto;

    listen-on    { any; };
    listen-on-v6 { none; };

    allow-query  { any; };
};
CONF_OPT

# ── 6. Validar ───────────────────────────────────────────────────────────────
echo "[6/6] Validando con named-checkzone y named-checkconf..."
echo ""
echo "  --> Zona directa:"
named-checkzone "${DOMAIN}" "${ZONE_DIR}/${ZONE_FILE_FWD}"
echo ""
echo "  --> Zona inversa:"
named-checkzone "${REVERSE_ZONE}" "${ZONE_DIR}/${ZONE_FILE_REV}"
echo ""
named-checkconf && echo "  --> named-checkconf: OK"

# Reiniciar BIND9
systemctl restart named
systemctl enable named

echo ""
echo "============================================================"
echo " BIND9 listo para: ${DOMAIN}"
echo "============================================================"
echo ""
echo " Test desde cliente (configurar nameserver ${IP_DNS} primero):"
echo "   nslookup dns.${DOMAIN} ${IP_DNS}"
echo "   nslookup web.${DOMAIN} ${IP_DNS}"
echo "   nslookup ftp.${DOMAIN} ${IP_DNS}"
echo "   nslookup ${IP_DNS}     ${IP_DNS}  # PTR inverso"
echo ""
echo " /etc/resolv.conf del cliente:"
echo "   nameserver ${IP_DNS}"
echo "   search ${DOMAIN}"
echo "============================================================"
