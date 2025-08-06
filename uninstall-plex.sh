#!/usr/bin/env bash
# Safe Uninstall Script for Plex + Docker Setup

set -euo pipefail

# === CONFIG (must match install-plex.sh) ==============================
MODE="local"                         # "nas" or "local"
PLEX_INSTANCE="plex"

NAS_IP=""                            # Needed if MODE="nas"
NAS_SHARE="videos/media"
SMB_VERS="3.0"
CIFS_MOUNT="/mnt/plex-media"
CREDS_FILE="/etc/samba/plex-media.cred"

CONFIG_DIR="$HOME/plex-config"
MEDIA_DIR="$HOME/media"
STACK_DIR="$HOME/plex-docker"
COMPOSE_FILE="$STACK_DIR/docker-compose.yml"
# ======================================================================

echo
echo "⚠️  WARNING: This script will remove your Plex Docker container, image, and related system config files."
echo "✅ Your actual media content (movies, shows, etc.) will NOT be touched unless you confirm it explicitly."
echo

read -rp "Are you sure you want to proceed with uninstalling Plex? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
  echo "❌ Uninstall canceled."
  exit 0
fi

echo
echo "[+] Stopping and removing Plex container..."
docker compose -f "$COMPOSE_FILE" down --remove-orphans || true
docker rm -f "$PLEX_INSTANCE" 2>/dev/null || true
docker image rm ghcr.io/linuxserver/plex -f 2>/dev/null || true

if [[ "$MODE" == "nas" ]]; then
  echo "[+] Unmounting NAS share..."
  sudo umount "$CIFS_MOUNT" 2>/dev/null || true

  echo "[+] Removing NAS fstab entry..."
  sudo sed -i "\|^//${NAS_IP}/${NAS_SHARE} |d" /etc/fstab

  if [[ -f "$CREDS_FILE" ]]; then
    read -rp "[?] Delete NAS credentials file at $CREDS_FILE? [y/N]: " reply
    [[ "$reply" =~ ^[Yy]$ ]] && sudo rm -f "$CREDS_FILE"
  fi

  if [[ -d "$CIFS_MOUNT" ]]; then
    read -rp "[?] Delete NAS mount folder at $CIFS_MOUNT? [y/N]: " reply
    [[ "$reply" =~ ^[Yy]$ ]] && sudo rmdir "$CIFS_MOUNT"
  fi
fi

read -rp "[?] Delete Plex config directory at $CONFIG_DIR? [y/N]: " delconf
[[ "$delconf" =~ ^[Yy]$ ]] && rm -rf "$CONFIG_DIR"

read -rp "[?] Delete media directory at $MEDIA_DIR? (Your actual media files will not be touched) [y/N]: " delmedia
[[ "$delmedia" =~ ^[Yy]$ ]] && rm -rf "$MEDIA_DIR"

read -rp "[?] Delete Docker stack directory at $STACK_DIR? [y/N]: " delstack
[[ "$delstack" =~ ^[Yy]$ ]] && rm -rf "$STACK_DIR"

echo
echo "✅ Plex uninstall complete. Media files were not altered unless explicitly confirmed."

