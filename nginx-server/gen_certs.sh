#!/bin/bash

set -e

# Generate self-signed SSL certificate

read -rp "Enter your domain or IP [e.g. 192.168.1.10 or example.com]: " CN

if [[ -z "$CN" ]]; then
  echo "ERROR: Domain or IP cannot be empty." >&2
  exit 1
fi

mkdir -p certs

openssl req -x509 -newkey rsa:2048 -nodes \
  -keyout certs/server.key \
  -out certs/server.crt \
  -days 365 \
  -subj "/CN=$CN"

chmod 600 certs/server.key

echo ""
echo "============================================"
echo "  Certificate generated successfully!"
echo "============================================"
echo "  CN (domain/IP) : $CN"
echo "  Private key    : certs/server.key"
echo "  Certificate    : certs/server.crt"
echo "  Expires in     : 365 days"