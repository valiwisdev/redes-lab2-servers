#!/bin/bash

set -e

# FTP Server setup with ProFTPD + Docker

# 1. Get host IP
IP=$(ip -o -4 route show to default | awk '{print $5}' | head -1 | xargs -I{} ip -o -4 addr show {} | awk '{print $4}' | cut -d'/' -f1)

echo "============================================"
echo "  ProFTPD Docker Setup"
echo "============================================"
echo "  Detected IP : $IP"
echo ""

# 2. Prompt for config values
read -rp "Enter FTP username   [default: ftpuser]: " INPUT_USER
FTPUSER="${INPUT_USER:-ftpuser}"

read -rp "Enter FTP password   [default: ftppassword]: " INPUT_PASS
FTPPASS="${INPUT_PASS:-ftppassword}"

# PASV address is required - no default skipping allowed
while true; do
  read -rp "Enter PASV/server IP [detected: $IP]: " INPUT_IP
  SERVER_IP="${INPUT_IP:-$IP}"
  if [[ -n "$SERVER_IP" ]]; then
    break
  fi
  echo "  ERROR: IP is required for passive mode to work." >&2
done

# 3. Create ftp_data folder
echo ""
echo "  Creating ./ftp_data folder..."
mkdir -p ftp_data

# 4. Create docker-compose.yml
echo "  Creating docker-compose.yml..."
cat > docker-compose.yml << EOF
services:
  proftpd:
    image: instantlinux/proftpd
    container_name: proftpd
    ports:
      - "21:21"
      - "30000-30009:30000-30009"
    environment:
      - FTPUSER_NAME=$FTPUSER
      - FTPUSER_PASS=$FTPPASS
      - FTPUSER_UID=1000
      - FTPUSER_GID=1000
      - PASV_ADDRESS=$SERVER_IP
      - PASV_MIN_PORT=30000
      - PASV_MAX_PORT=30009
    volumes:
      - ./ftp_data:/home/$FTPUSER
    restart: unless-stopped
EOF

# 5. Start the service
echo "  Starting ProFTPD container..."
docker compose up -d

echo ""
echo "============================================"
echo "  FTP Server is up!"
echo "============================================"
echo "  Host     : $SERVER_IP"
echo "  Port     : 21"
echo "  User     : $FTPUSER"
echo "  Password : $FTPPASS"
echo "  Mode     : Passive (30000-30009)"
echo "  Files    : $(pwd)/ftp_data"
echo ""
echo "  FileZilla: connect with the above credentials"
echo "  Logs    : docker compose logs proftpd"
