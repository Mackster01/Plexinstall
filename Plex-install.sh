#!/usr/bin/env bash
# Version 2 – Easy Docker Plex Install Script (NAS & Local support)
set -euo pipefail

# ===== BEGIN CONFIG ===================================================
MODE="local"                     # "nas" or "local"

# If MODE="nas", fill these (ignored for MODE="local"):
NAS_IP="."                        # e.g., 192.168.4.45
NAS_SHARE="videos/media"         # Path on NAS
NAS_USER="your-nas-username"
NAS_PASS="your-nas-password"
SMB_VERS="3.0"                   # or 2.1, depending on NAS

# If MODE="local", set your media directory:
LOCAL_MEDIA_DIR="$HOME/media"

# Optional - Make sure to copy/paste the claim # BEFORE running script!
PLEX_CLAIM=""                    # claim-xxxxxxxx
TZ="America/Chicago"             # Replace with your timezone
# ===== END CONFIG =====================================================

# --- Derived paths: no need to not modify---
PUID="$(id -u)"
PGID="$(id -g)"
CONFIG_DIR="$HOME/plex-config"
STACK_DIR="$HOME/plex-docker"
COMPOSE_FILE="$STACK_DIR/docker-compose.yml"
CIFS_MOUNT="/mnt/plex-media"
CREDS_FILE="/etc/samba/plex-media.cred"

# --- Step 1: Install Docker & Compose (via Docker APT repo) ---
echo "[+] Installing Docker and Docker Compose from Docker's official repository..."

# 1. Transport & keyring tools
sudo apt update
sudo apt install -y ca-certificates curl gnupg cifs-utils

# 2. Add Docker's GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# 3. Add Docker’s APT repo
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# 4. Install Docker + Compose plugin
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# 5. Enable and start Docker
sudo systemctl enable --now docker

# --- Step 2: Add user to docker group ---
if ! id -nG "$USER" | grep -qw docker; then
  echo "[+] Adding $USER to docker group..."
  sudo usermod -aG docker "$USER"
  echo "⚠️  Please log out and back in for group changes to apply!"
fi

# --- Step 3: Create required folders ---
echo "[+] Creating config and stack directories..."
mkdir -p "$CONFIG_DIR" "$STACK_DIR"

# --- Step 4: Determine media path ---
if [[ "$MODE" == "nas" ]]; then
  echo "[+] MODE=nas — mounting NAS share..."

  sudo mkdir -p "$CIFS_MOUNT"
  MEDIA_PATH="$CIFS_MOUNT"

  # Create credentials file
  if [[ ! -f "$CREDS_FILE" ]]; then
    echo "[+] Creating NAS credentials file..."
    echo -e "username=$NAS_USER\npassword=$NAS_PASS" | sudo tee "$CREDS_FILE" >/dev/null
    sudo chmod 600 "$CREDS_FILE"
    sudo chown root:root "$CREDS_FILE"
  fi

  # Add to fstab if not already present
  FSTAB_LINE="//${NAS_IP}/${NAS_SHARE} ${CIFS_MOUNT} cifs credentials=${CREDS_FILE},uid=${PUID},gid=${PGID},iocharset=utf8,vers=${SMB_VERS},_netdev 0 0"
  if ! grep -qsE "^//${NAS_IP}/${NAS_SHARE}[[:space:]]" /etc/fstab; then
    echo "[+] Adding mount to /etc/fstab..."
    echo "$FSTAB_LINE" | sudo tee -a /etc/fstab >/dev/null
  fi

  echo "[+] Mounting NAS share..."
  sudo mount -a

else
  echo "[+] MODE=local — using local media directory: $LOCAL_MEDIA_DIR"
  mkdir -p "$LOCAL_MEDIA_DIR"
  MEDIA_PATH="$LOCAL_MEDIA_DIR"
fi

# --- Step 5: Write docker-compose.yml ---
echo "[+] Writing docker-compose.yml..."
cat > "$COMPOSE_FILE" <<EOF
services:
  plex:
    image: ghcr.io/linuxserver/plex
    container_name: plex
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
$( [ -n "$PLEX_CLAIM" ] && echo "      - PLEX_CLAIM=${PLEX_CLAIM}" )
    volumes:
      - ${CONFIG_DIR}:/config
      - ${MEDIA_PATH}:/data
    ports:
      - "32400:32400"
    restart: unless-stopped
EOF

# --- Step 6: Start Plex ---
echo "[+] Starting Plex container...!!"
sudo docker compose -f "$COMPOSE_FILE" up -d

# --- Final Info ---
echo
echo "✅ Plex is now starting!"
echo "   - Local:  http://localhost:32400/web"
echo "   - LAN:    http://<your-ip>:32400/web"
if ! id -nG "$USER" | grep -qw docker; then
  echo "🔁 Reminder: You must log out and back in before you can run 'docker' without sudo."
fi
