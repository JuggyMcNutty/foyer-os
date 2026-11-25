#!/bin/sh
# install-on-box.sh (interim; superseded by scripts/provision.sh) — runs ON the HTPC box (root@192.168.1.123).
# Assumes sources + configs were rsynced to /opt/htpc/src and /opt/htpc/session
# by push-to-box.sh. Idempotent: safe to re-run.

set -e

SRC=/opt/htpc/src
CONF=/opt/htpc/session
LAUNCHER_DIR=/opt/htpc/launcher

echo "==> adding remaining packages"
apk add qt6-qtsvg qt6-qtwebchannel qt6-qtdeclarative qt6-qtmultimedia chromium mpv yt-dlp wireplumber \
    spdlog-dev fmt-dev sdl3_ttf-dev sdl3-dev libxml2-dev \
    xwayland hwdata seatd cmd:seatd-launch eudev eudev-openrc libinput-udev \
    mpv-dev sdl2-dev libcec-dev qt6-qtbase-private-dev python3-dev \
    wpa_supplicant bluez bluez-openrc dbus dbus-openrc iw wpctl libevdev libevdev-dev

# session stack: udev (libinput enumeration) + seatd (wlroots seat)
rc-update add udev sysinit 2>/dev/null || true
rc-update add udev-trigger sysinit 2>/dev/null || true
rc-update add seatd default 2>/dev/null || true
# WiFi + Bluetooth services (fail-safe without radios present)
rc-update add dbus default 2>/dev/null || true
rc-update add bluetooth default 2>/dev/null || true

echo "==> building SDL3_image (not packaged in Alpine 3.24)"
mkdir -p "$SRC"
if [ ! -d "$SRC/SDL_image" ]; then
    git clone --depth 1 https://github.com/libsdl-org/SDL_image "$SRC/SDL_image"
fi
cmake -S "$SRC/SDL_image" -B "$SRC/SDL_image/build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr/local
cmake --build "$SRC/SDL_image/build"
cmake --install "$SRC/SDL_image/build"

echo "==> building foyer (launcher)"
cmake -S "$SRC/foyer" -B "$SRC/foyer/build" -DCMAKE_BUILD_TYPE=Release
cmake --build "$SRC/foyer/build"

echo "==> building Red"
cmake -S "$SRC/red" -B "$SRC/red/build" -DCMAKE_BUILD_TYPE=Release -DRED_BUILD_TESTS=OFF -DCMAKE_SKIP_INSTALL_RPATH=ON
cmake --build "$SRC/red/build"
cmake --install "$SRC/red/build" --prefix /usr/local

echo "==> building Jellyfin Desktop (official Qt6+mpv client)"
cmake -S "$SRC/jellyfin-desktop" -B "$SRC/jellyfin-desktop/build" -DCMAKE_BUILD_TYPE=Release \
    -DUSE_STATIC_MPVQT=ON -DBUILD_TESTING=OFF -DCHECK_FOR_UPDATES=OFF
cmake --build "$SRC/jellyfin-desktop/build"
cmake --install "$SRC/jellyfin-desktop/build" --prefix /usr/local

echo "==> installing launcher tree"
mkdir -p "$LAUNCHER_DIR"
cp "$SRC/foyer/build/src/foyer" "$LAUNCHER_DIR/foyer.new" && mv "$LAUNCHER_DIR/foyer.new" "$LAUNCHER_DIR/foyer"
rm -f "$LAUNCHER_DIR/big-launcher"
rm -rf "$LAUNCHER_DIR/assets"
cp -r "$SRC/big-launcher-assets/assets" "$LAUNCHER_DIR/assets"
# overlay our custom icons
cp "$CONF/icons/"*.svg "$LAUNCHER_DIR/assets/icons/"

echo "==> /etc/foyer (legacy /etc/htpc becomes a symlink)"
if [ -d /etc/htpc ] && [ ! -L /etc/htpc ] && [ ! -d /etc/foyer ]; then
    mv /etc/htpc /etc/foyer
fi
mkdir -p /etc/foyer
[ -L /etc/htpc ] || { rm -rf /etc/htpc; ln -s foyer /etc/htpc; }
# Launcher config: keep user edits (the layout editor writes these)
for f in config.ini layout.xml; do
    if [ ! -f "/etc/foyer/$f" ]; then
        if [ -f "$LAUNCHER_DIR/$f" ]; then mv "$LAUNCHER_DIR/$f" "/etc/foyer/$f"; else cp "$CONF/$f" "/etc/foyer/$f"; fi
    fi
done
# migrate legacy htpc-<app> commands in an existing layout
sed -i -E 's#<command>htpc-(jellyfin|youtube|amazon|twitch|iptv)</command>#<command>foyer-app \1</command>#; s#<command>htpc-red</command>#<command>foyer-app youtube</command>#' /etc/foyer/layout.xml
rm -f "$LAUNCHER_DIR/config.ini" "$LAUNCHER_DIR/layout.xml"
cp "$CONF/"*.url "$CONF/iptv.m3u" /etc/foyer/
printf '%s\n' 'Mozilla/5.0 (Linux; Tizen 2.3; SmartHub; SMART-TV) AppleWebKit/538.1 (KHTML, like Gecko) TV Safari/538.1' > /etc/foyer/smarttv-ua

echo "==> installing foyer-app / foyer-ctl (+ htpc-* compat symlinks)"
install -m 755 "$CONF/bin/foyer-app" /usr/local/bin/foyer-app
install -m 755 "$CONF/bin/foyer-ctl" /usr/local/bin/foyer-ctl
rm -f /usr/local/bin/htpc-app /usr/local/bin/htpc-ctl /usr/local/bin/htpc-red
ln -sf foyer-ctl /usr/local/bin/htpc-ctl
ln -sf foyer-ctl /usr/local/bin/htpc-net
ln -sf foyer-app /usr/local/bin/htpc-app
for app in jellyfin youtube amazon twitch iptv; do
    ln -sf foyer-app "/usr/local/bin/htpc-$app"
done

echo "==> session.conf (kept if present)"
if [ ! -f /etc/foyer/session.conf ]; then
    printf '%s\n' \
        '# foyer-os session display mode. Rewritten by `foyer-ctl display mode/set`.' \
        '# Leave WIDTH/HEIGHT empty to use the monitor preferred mode.' \
        '# RENDER_WIDTH/RENDER_HEIGHT: internal render size (defaults to output size).' \
        'WIDTH=1920' 'HEIGHT=1080' 'RATE=60' > /etc/foyer/session.conf
fi

echo "==> installing session script"
install -m 755 "$CONF/session.sh" /etc/foyer/session.sh

echo "==> wiring autostart on tty1"
sed -i 's|^tty1::.*|tty1::respawn:/bin/sh /etc/foyer/session.sh|' /etc/inittab
grep -n "^tty1::" /etc/inittab

echo "==> killing stale pipewire openrc defaults (we run it in-session)"
rc-update delete pipewire default 2>/dev/null || true
rc-update delete pipewire-pulse default 2>/dev/null || true

echo
echo "INSTALL COMPLETE. Reboot the box (or: kill 1 on tty1 session) to start the HTPC UI."
echo "Verify from dev machine after reboot: ssh htpc 'pgrep -a gamescope; pgrep -a pipewire'"