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

while true; do
  read -rp "Enter PASV/server IP [detected: $IP]: " INPUT_IP
  SERVER_IP="${INPUT_IP:-$IP}"
  if [[ -n "$SERVER_IP" ]]; then
    break
  fi
  echo "  ERROR: IP is required for passive mode to work." >&2
done

# 3. Create folders
echo ""
echo "  Creating folders..."
mkdir -p ftp_data
mkdir -p proftpd

# 4. Create Dockerfile
echo "  Creating Dockerfile..."
cat > proftpd/Dockerfile << EOF
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y proftpd-basic && rm -rf /var/lib/apt/lists/*

RUN useradd -m -d /home/ftp/$FTPUSER -s /bin/bash $FTPUSER && \
    echo "$FTPUSER:$FTPPASS" | chpasswd

RUN mkdir -p /home/ftp/$FTPUSER && chown $FTPUSER:$FTPUSER /home/ftp/$FTPUSER

COPY proftpd.conf /etc/proftpd/proftpd.conf

EXPOSE 21 30000-30009

CMD ["proftpd", "--nodaemon"]
EOF

# 5. Create proftpd.conf
echo "  Creating proftpd.conf..."
cat > proftpd/proftpd.conf << EOF
ServerName "FTP Server"
ServerType standalone
DefaultServer on
Port 21
Umask 022
MaxInstances 30
User proftpd
Group nogroup
DefaultRoot /home/ftp/$FTPUSER $FTPUSER
AuthOrder mod_auth_unix.c

PassivePorts 30000 30009
MasqueradeAddress $SERVER_IP

<Directory /home/ftp/$FTPUSER>
  Umask 022 022
  AllowOverwrite on
</Directory>

<Limit LOGIN>
  AllowUser $FTPUSER
  DenyAll
</Limit>
EOF

# 6. Create docker-compose.yml
echo "  Creating docker-compose.yml..."
cat > docker-compose.yml << EOF
services:
  proftpd:
    build: ./proftpd
    container_name: proftpd
    ports:
      - "21:21"
      - "30000-30009:30000-30009"
    volumes:
      - ./ftp_data:/home/ftp/$FTPUSER
    restart: unless-stopped
EOF

# 7. Start the service
echo "  Building and starting ProFTPD container..."
docker compose up -d --build

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
echo "  Logs    : docker compose logs proftpd"
