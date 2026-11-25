#!/bin/sh
# push-to-box.sh — runs on the DEV machine. Syncs sources/config to the box,
# then triggers the box-side installer.

set -e
HTPC_HOST="${HTPC_HOST:-root@192.168.1.123}"
PROJ="$(cd "$(dirname "$0")/.." && pwd)"

ssh "$HTPC_HOST" 'mkdir -p /opt/htpc/src /opt/htpc/session'

echo "==> rsyncing foyer (launcher submodule)"
rsync -a --delete --exclude build/ --exclude .git \
    "$PROJ/foyer/" "$HTPC_HOST:/opt/htpc/src/foyer/"

echo "==> rsyncing assets"
rsync -a --delete \
    "$PROJ/big-launcher-assets/" "$HTPC_HOST:/opt/htpc/src/big-launcher-assets/"

echo "==> rsyncing Red"
rsync -a --delete --exclude build/ --exclude .git/ \
    "$PROJ/red/" "$HTPC_HOST:/opt/htpc/src/red/"

echo "==> rsyncing jellyfin-desktop (official Qt6+mpv client)"
rsync -a --delete --exclude build/ --exclude .git/ \
    "$PROJ/jellyfin-desktop/" "$HTPC_HOST:/opt/htpc/src/jellyfin-desktop/"

echo "==> rsyncing session config"
rsync -a --delete \
    "$PROJ/session/" "$HTPC_HOST:/opt/htpc/session/"

echo "==> running installer on box"
rsync -a "$PROJ/htpc-setup/install-on-box.sh" "$HTPC_HOST:/opt/htpc/"
ssh "$HTPC_HOST" 'chmod +x /opt/htpc/install-on-box.sh && /bin/sh /opt/htpc/install-on-box.sh'