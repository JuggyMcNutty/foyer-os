#!/bin/sh
# build-debs.sh — build foyer-os .debs for Debian trixie (glibc) inside the
# rootless Debian sandbox. Output: out/debs/trixie/*.deb
#
#   scripts/build-debs.sh [foyer foyer-session foyer-update foyer-red foyer-jellyfin-desktop]
#
# foyer is built against trixie's own SDL3 packages (shared). Red needs
# Qt >= 6.11, which trixie lacks (6.8) -> foyer-red is built with the
# bundled-Qt fallback disabled and skipped unless FOYER_DEB_RED=1.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
PKGS="${*:-foyer foyer-session foyer-update foyer-jellyfin-desktop}"
exec "$HERE/debian-env.sh" --suite trixie /bin/sh -eu${FOYER_TRACE:+x} -s -- $PKGS <<'INNER'
. /work/debian/packages.sh
cat > /etc/apt/sources.list <<SRC
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main
deb http://deb.debian.org/debian trixie-backports main contrib
deb http://security.debian.org/debian-security trixie-security main
SRC
apt-get update -qq
apt-get install -y -qq build-essential cmake ninja-build pkg-config dpkg-dev fakeroot git curl ca-certificates >/dev/null
OUT=/work/out/debs/trixie
mkdir -p "$OUT"
ARCH=$(dpkg --print-architecture)
# dpkg-shlibdeps wants a source package context
mkdir -p /tmp/shl/debian && printf 'Source: foyer\n\nPackage: foyer\nArchitecture: any\n' > /tmp/shl/debian/control

mkdeb() {   # name version arch depends description [conffiles...]
    n=$1 v=$2 a=$3 dep=$4 desc=$5; shift 5
    mkdir -p "$D/DEBIAN"
    {
        echo "Package: $n"
        echo "Version: $v"
        echo "Architecture: $a"
        echo "Maintainer: JuggyMcNutty <JuggyMcNutty@users.noreply.github.com>"
        [ -n "$dep" ] && echo "Depends: $dep"
        echo "Section: misc"
        echo "Priority: optional"
        echo "Homepage: https://github.com/JuggyMcNutty/foyer-os"
        echo "Installed-Size: $(du -sk "$D" | cut -f1)"
        echo "Description: $desc"
    } > "$D/DEBIAN/control"
    : > "$D/DEBIAN/conffiles"
    for c in "$@"; do echo "$c" >> "$D/DEBIAN/conffiles"; done
    [ -s "$D/DEBIAN/conffiles" ] || rm "$D/DEBIAN/conffiles"
    dpkg-deb --root-owner-group -Zxz --build "$D" "$OUT/${n}_${v}_${a}.deb" >/dev/null
    echo "built $OUT/${n}_${v}_${a}.deb"
}

for p in "$@"; do
  D=/tmp/deb-$p; rm -rf "$D"; mkdir -p "$D"
  case $p in
  foyer)
    apt-get install -y -qq libsdl3-dev libsdl3-ttf-dev libsdl3-image-dev libxml2-dev libfmt-dev libspdlog-dev libevdev-dev >/dev/null
    B=/tmp/b-foyer; rm -rf $B
    cmake -S /work/foyer -B $B -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr >/dev/null
    cmake --build $B >/dev/null
    SDL_VIDEO_DRIVER=dummy $B/tests/foyer_tests | tail -1
    DESTDIR=$D cmake --install $B >/dev/null
    strip $D/usr/bin/foyer
    DEPS=$(cd /tmp/shl && dpkg-shlibdeps -O $D/usr/bin/foyer 2>/dev/null | sed 's/^shlibs:Depends=//') || true
    [ -n "$DEPS" ] || DEPS="libsdl3-0, libsdl3-ttf0, libsdl3-image0, libxml2, libfmt10, libspdlog1.15, libevdev2"
    mkdeb foyer "$FOYER_VER-$DEB_REV" $ARCH "$DEPS" "Couch-first big-picture launcher for TVs"
    ;;
  foyer-session)
    S=/work/session
    install -Dm755 $S/bin/foyer-ctl $D/usr/bin/foyer-ctl
    install -Dm755 $S/bin/foyer-app $D/usr/bin/foyer-app
    install -Dm755 $S/session.sh $D/usr/lib/foyer/session.sh
    for f in $S/*.url $S/iptv.m3u; do install -Dm644 "$f" $D/etc/foyer/$(basename "$f"); done
    printf 'WIDTH=\nHEIGHT=\nRATE=\n' > $D/etc/foyer/session.conf
    install -Dm644 $S/systemd/foyer-session.service $D/usr/lib/systemd/system/foyer-session.service
    install -Dm644 $S/backend_systemd.sh $D/usr/lib/foyer/backend_systemd.sh
    mkdir -p $D/etc/foyer/apps.d $D/etc/foyer/themes $D/etc/foyer/art
    cat > $D/DEBIAN.postinst <<'PI'
#!/bin/sh
set -e
if [ "$1" = configure ] && [ -d /run/systemd/system ] || [ -x /bin/systemctl ]; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    systemctl disable getty@tty1.service >/dev/null 2>&1 || true
    systemctl enable foyer-session.service seatd.service NetworkManager.service >/dev/null 2>&1 || true
fi
[ -e /etc/htpc ] || ln -s foyer /etc/htpc
exit 0
PI
    mkdir -p $D/DEBIAN && mv $D/DEBIAN.postinst $D/DEBIAN/postinst && chmod 755 $D/DEBIAN/postinst
    mkdeb foyer-session "$FOYER_VER-$DEB_REV" all "$SESSION_DEPS" "foyer-os session: gamescope + PipeWire + Foyer on tty1" \
        /etc/foyer/session.conf /etc/foyer/jellyfin.url /etc/foyer/amazon.url /etc/foyer/twitch.url /etc/foyer/iptv.m3u
    ;;
  foyer-update)
    install -Dm755 /work/session/bin/foyer-update $D/usr/bin/foyer-update
    mkdeb foyer-update "$FOYER_VER-$DEB_REV" all "curl, ca-certificates" "Update foyer-os packages from GitHub releases"
    ;;
  foyer-jellyfin-desktop)
    apt-get install -y -qq qt6-base-dev qt6-base-private-dev qt6-webengine-dev qt6-webchannel-dev qt6-declarative-dev \
        qt6-declarative-private-dev libmpv-dev libsdl2-dev libcec-dev python3 extra-cmake-modules >/dev/null
    # pinned versions shared with the APKBUILD
    A=/work/aports/foyer-jellyfin-desktop/APKBUILD
    pkgver=$(sed -n 's/^pkgver=//p' $A); _tag=$(sed -n 's/^_tag=//p' $A); _mpvqt=$(sed -n 's/^_mpvqt=//p' $A)
    T=/tmp/jf; rm -rf $T; mkdir -p $T
    curl -fsSL "https://github.com/jellyfin/jellyfin-desktop/archive/refs/tags/$_tag.tar.gz" | tar -xz -C $T
    curl -fsSL "https://invent.kde.org/libraries/mpvqt/-/archive/$_mpvqt/mpvqt-$_mpvqt.tar.gz" | tar -xz -C $T
    SRC=$(ls -d $T/jellyfin-desktop-*)
    rm -rf $SRC/external/mpvqt && mv $T/mpvqt-$_mpvqt $SRC/external/mpvqt
    cmake -S $SRC -B $T/b -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr -DUSE_STATIC_MPVQT=ON \
        -DBUILD_TESTING=OFF -DCHECK_FOR_UPDATES=OFF >/dev/null
    cmake --build $T/b >/dev/null
    DESTDIR=$D cmake --install $T/b >/dev/null
    DEPS=$(cd /tmp/shl && dpkg-shlibdeps -O $D/usr/bin/jellyfin-desktop 2>/dev/null | sed 's/^shlibs:Depends=//') || true
    mkdeb foyer-jellyfin-desktop "$(echo "$pkgver" | tr _ '~')-$DEB_REV" $ARCH "${DEPS:-libqt6webenginecore6, libmpv2}" \
        "Jellyfin desktop client (Qt6 + mpv), built for Foyer"
    ;;
  *) echo "unknown package $p" >&2; exit 1 ;;
  esac
done
ls -la "$OUT"
INNER
