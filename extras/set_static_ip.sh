#!/bin/bash

set -e

# Static IP configuration - Ubuntu Server
# Based on Lab #2 - Infraestructura de Comunicaciones

# 1. Detect network interface and current DHCP IP
INTERFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -1)
CURRENT_IP=$(ip -o -4 addr show "$INTERFACE" | awk '{print $4}' | head -1)
IP_ONLY=$(echo "$CURRENT_IP" | cut -d'/' -f1)
PREFIX=$(echo "$CURRENT_IP" | cut -d'/' -f2)

echo "============================================"
echo "  Ubuntu Server - Static IP Setup"
echo "============================================"
echo "  Interface detected : $INTERFACE"
echo "  Current IP (DHCP)  : $IP_ONLY/$PREFIX"
echo ""

# 2. Prompt user for values (defaults = current DHCP values)
read -rp "Enter IP address   [default: $IP_ONLY]: " INPUT_IP
IP_ADDR="${INPUT_IP:-$IP_ONLY}"

read -rp "Enter prefix/mask  [default: $PREFIX]: " INPUT_PREFIX
MASK="${INPUT_PREFIX:-$PREFIX}"

DEFAULT_GW=$(ip route | awk '/default/ {print $3}' | head -1)
read -rp "Enter gateway      [default: $DEFAULT_GW]: " INPUT_GW
GATEWAY="${INPUT_GW:-$DEFAULT_GW}"

# 3. Find the netplan config file
NETPLAN_FILE=$(ls /etc/netplan/*.yaml 2>/dev/null | head -1)
if [[ -z "$NETPLAN_FILE" ]]; then
  echo "ERROR: No netplan YAML file found in /etc/netplan/" >&2
  exit 1
fi

echo ""
echo "  Netplan file       : $NETPLAN_FILE"
echo "  Applying config    : $IP_ADDR/$MASK via $GATEWAY"
echo ""

# 4. Backup the original file
BACKUP="${NETPLAN_FILE}.bak.$(date +%Y%m%d%H%M%S)"
sudo cp "$NETPLAN_FILE" "$BACKUP"
echo "  Backup saved to    : $BACKUP"

# 5. Write new netplan config
sudo tee "$NETPLAN_FILE" > /dev/null << YAML
network:
  version: 2
  ethernets:
    $INTERFACE:
      dhcp4: no
      addresses: [$IP_ADDR/$MASK]
      routes:
        - to: default
          via: $GATEWAY
YAML

echo "  New netplan config written."

# 6. Apply the configuration
echo "  Applying netplan..."
sudo netplan apply

echo ""
echo "============================================"
echo "  Static IP configured successfully!"
echo "============================================"
echo ""
echo "  Verification steps:"
echo "    1. ip a                  -> confirm $IP_ADDR is shown"
echo "    2. ping -c 4 8.8.8.8    -> verify internet"
echo "    3. ping -c 4 $GATEWAY   -> verify gateway"
