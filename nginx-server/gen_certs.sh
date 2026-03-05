#!/bin/bash

set -e

cd "$(dirname "${BASH_SOURCE[0]}")"

IP=$(ip -o -4 route show to default | awk '{print $5}' | head -1 | xargs -I{} ip -o -4 addr show {} | awk '{print $4}' | cut -d'/' -f1)

if [[ -z "$IP" ]]; then
  echo "ERROR: Could not detect machine IP." >&2
  exit 1
fi

echo "Detected IP: $IP"

mkdir -p certs

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout certs/server.key \
  -out certs/server.crt \
  -days 365 \
  -subj "/CN=$IP"

chmod 600 certs/server.key

echo ""
echo "============================================"
echo "  Certificate generated successfully!"
echo "============================================"
echo "  CN (IP)        : $IP"
echo "  Private key    : certs/server.key"
echo "  Certificate    : certs/server.crt"
echo "  Expires in     : 365 days"
