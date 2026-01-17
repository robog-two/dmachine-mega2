#!/bin/bash
set -euo pipefail

echo "=== Starting one-time system initialization ==="

# Install docker, setup, & run the Grapevine indexer

# Update the apt package index
apt-get update

# Install packages to allow apt to use a repository over HTTPS
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker’s official GPG key
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Set up the stable repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
  https://download.docker.com/linux/debian \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Refresh the package index and install Docker Engine
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io

# Verify the installation
docker --version

git clone https://github.com/robog-two/grapevine.git /tmp/grapevine

cd /tmp/grapevine;
git checkout genai-here-only;
docker compose up --build

# I needed a frivolous commit to trigger a restore because something broke.
