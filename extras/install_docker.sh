#!/bin/bash

set -e

echo "==> Adding Docker's official GPG key..."
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "==> Adding Docker repository to Apt sources..."
sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

sudo apt update

echo "==> Installing Docker..."
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "==> Adding current user to the docker group..."
sudo groupadd docker 2>/dev/null || true
sudo usermod -aG docker "$USER"

echo ""
echo "✅ Docker installation complete!"
echo "   Please log out and back in (or run 'newgrp docker') for group changes to take effect."
echo "   Verify installation with: docker run hello-world"
