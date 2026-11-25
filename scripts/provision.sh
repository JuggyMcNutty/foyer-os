#!/bin/sh
# provision.sh — turn a stock Alpine install into foyer-os, over SSH.
#
#   scripts/provision.sh PROFILE [user@]HOST [--apks DIR | --release TAG]
#
# Installs the profile's packages from the official Alpine mirrors plus the
# foyer-os APKs (local out/apks/<arch>/ by default, or a GitHub release) with
# --allow-untrusted, writes /etc/foyer/session.conf for the profile and wires
# the session. Nothing is compiled on the target. Idempotent; re-run to update.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
. "$HERE/lib-profile.sh"
. "$HERE/alpine.lock"

[ $# -ge 2 ] || { sed -n '2,9p' "$0"; exit 2; }
load_profile "$1"; HOST=$2; shift 2
SRC=local; APKS="$REPO/out/apks/$ARCH"; TAG=""
while [ $# -gt 0 ]; do
    case "$1" in
        --apks) APKS=$2; shift 2 ;;
        --release) SRC=release; TAG=$2; shift 2 ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac
done
[ "$BASE" = alpine ] || { echo "provision.sh: BASE=$BASE not supported yet (use scripts/provision-debian.sh)" >&2; exit 1; }

PKGS=$(profile_pkgs)
SESSION_CONF=$(profile_session_conf)
echo "==> provisioning $HOST as '$PROFILE_TITLE' ($PROFILE_NAME)"

STAGE=/tmp/foyer-provision
ssh "$HOST" "rm -rf $STAGE && mkdir -p $STAGE"
if [ $SRC = local ]; then
    ls "$APKS"/foyer-*.apk >/dev/null 2>&1 || { echo "no APKs in $APKS (run scripts/build-apks.sh)" >&2; exit 1; }
    echo "==> copying APKs from $APKS"
    scp -q "$APKS"/*.apk "$HOST:$STAGE/"
fi

ssh "$HOST" STAGE="$STAGE" PKGS="$PKGS" SRC="$SRC" TAG="$TAG" HOSTNAME_="$HOSTNAME" \
    ALPINE_BRANCH="$ALPINE_BRANCH" ALPINE_MIRROR="$ALPINE_MIRROR" SWAP_MB="$SWAP_MB" \
    ASSET_BUDGET_MB="$ASSET_BUDGET_MB" PROFILE_NAME="$PROFILE_NAME" sh -s <<'REMOTE'
set -eu
echo "==> repositories ($ALPINE_BRANCH main + community)"
printf '%s/%s/main\n%s/%s/community\n' "$ALPINE_MIRROR" "$ALPINE_BRANCH" "$ALPINE_MIRROR" "$ALPINE_BRANCH" > /etc/apk/repositories
apk update -q
echo "==> profile packages"
# shellcheck disable=SC2086
apk add -q $PKGS
echo "==> foyer-os packages"
if [ "$SRC" = release ]; then
    # bootstrap foyer-update straight from the release, then let it install the rest
    apk add -q curl
    REL=$(curl -fsSL "https://api.github.com/repos/JuggyMcNutty/foyer-os/releases/tags/$TAG")
    U=$(printf '%s' "$REL" | sed -n 's/.*"browser_download_url": *"\([^"]*foyer-update-[^"]*\.apk\)".*/\1/p' | head -1)
    curl -fsSL -o "$STAGE/foyer-update.apk" "$U"
    apk add -q --allow-untrusted "$STAGE/foyer-update.apk"
    foyer-update "$TAG"
else
    apk add -q --allow-untrusted --upgrade "$STAGE"/foyer-sdl3_image-[0-9]*.apk "$STAGE"/foyer-[0-9]*.apk \
        "$STAGE"/foyer-session-*.apk "$STAGE"/foyer-update-*.apk \
        $(ls "$STAGE"/foyer-red-*.apk "$STAGE"/foyer-jellyfin-desktop-*.apk 2>/dev/null)
fi
# Remove pre-packaging leftovers (old /usr/local installs shadow packaged ones)
rm -f /usr/local/bin/foyer-ctl /usr/local/bin/foyer-app /usr/local/bin/htpc-*
[ -x /usr/bin/red ] && rm -f /usr/local/bin/red
[ -x /usr/bin/jellyfin-desktop ] && rm -f /usr/local/bin/jellyfin-desktop
rm -rf /opt/htpc/launcher
echo "$HOSTNAME_" > /etc/hostname; hostname "$HOSTNAME_" 2>/dev/null || true
# texture budget for this device
if [ -f /etc/foyer/settings.toml ] && grep -q '^asset_budget_mb' /etc/foyer/settings.toml; then
    sed -i "s/^asset_budget_mb.*/asset_budget_mb = $ASSET_BUDGET_MB/" /etc/foyer/settings.toml
fi
if [ "$SWAP_MB" -gt 0 ] && [ ! -f /swapfile ] && ! grep -q swap /etc/fstab; then
    dd if=/dev/zero of=/swapfile bs=1M count="$SWAP_MB" status=none && chmod 600 /swapfile && mkswap /swapfile >/dev/null
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    rc-update add swap boot >/dev/null 2>&1 || true
fi
for s in sshd chronyd networking; do rc-update add $s default >/dev/null 2>&1 || true; done
echo "$PROFILE_NAME" > /etc/foyer/profile
echo "==> done: $(apk info -v foyer foyer-session 2>/dev/null | tr '\n' ' ')"
REMOTE
# session.conf: profile defaults, but keep a mode the user already picked
printf '%s\n' "$SESSION_CONF" | ssh "$HOST" 'f=/etc/foyer/session.conf; if grep -q "^WIDTH=[0-9]" $f 2>/dev/null; then cat > /tmp/sc.new; grep "^RENDER_" /tmp/sc.new >> $f.tmp 2>/dev/null; grep -v "^RENDER_" $f >> $f.tmp; mv $f.tmp $f; else cat > $f; fi'
echo "==> provisioned. Restart the session: ssh $HOST 'kill -9 \$(pidof gamescope-wl gamescope)' or reboot."
