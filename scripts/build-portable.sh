#!/bin/sh
# build-portable.sh — portable glibc build of Foyer: compiled on Debian
# bookworm (glibc 2.36) with SDL3/SDL3_ttf/SDL3_image linked statically, so the
# binary runs on bookworm and anything newer (trixie, Ubuntu 24.04, Arch,
# Fedora). Output: out/foyer-<ver>-x86_64-glibc.tar.zst
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
exec "$HERE/debian-env.sh" --suite bookworm /bin/sh -eu -s <<'INNER'
apt-get update -qq
apt-get install -y -qq build-essential cmake ninja-build pkg-config git ca-certificates zstd \
    libfmt-dev libspdlog-dev libevdev-dev libfreetype-dev libharfbuzz-dev \
    libpng-dev libjpeg-dev libwebp-dev libdrm-dev libgbm-dev libegl-dev libgles-dev \
    libwayland-dev wayland-protocols libxkbcommon-dev libdecor-0-dev \
    libx11-dev libxext-dev libxcursor-dev libxi-dev libxrandr-dev libxss-dev libxfixes-dev libxtst-dev \
    libpulse-dev libpipewire-0.3-dev libasound2-dev libudev-dev libdbus-1-dev >/dev/null
B=/tmp/foyer-portable
cmake -S /work/foyer -B $B -G Ninja -DCMAKE_BUILD_TYPE=Release -DFOYER_BUNDLE_SDL=ON -DCMAKE_INSTALL_PREFIX=/usr >/dev/null
cmake --build $B
SDL_VIDEO_DRIVER=dummy $B/tests/foyer_tests | tail -1
VER=$(sed -n 's/^  VERSION \([0-9.]*\)$/\1/p' /work/foyer/CMakeLists.txt)
STAGE=/tmp/foyer-$VER-x86_64-glibc
rm -rf $STAGE && DESTDIR=$STAGE cmake --install $B >/dev/null
# drop static SDL dev files installed by the bundled subprojects
rm -rf $STAGE/usr/include $STAGE/usr/lib $STAGE/usr/share/licenses $STAGE/usr/share/doc/libxml2* $STAGE/usr/share/man $STAGE/usr/share/aclocal $STAGE/usr/share/gtk-doc $STAGE/usr/bin/xml2-config
strip $STAGE/usr/bin/foyer
echo "max glibc symbol: $(objdump -T $STAGE/usr/bin/foyer | grep -oE 'GLIBC_[0-9.]+' | sort -V -u | tail -1)"
echo "needs: $(objdump -p $STAGE/usr/bin/foyer | awk '/NEEDED/ {print $2}' | tr '\n' ' ')"
mkdir -p /work/out
tar -C $STAGE -cf - . | zstd -q -19 -T0 -o /work/out/foyer-$VER-x86_64-glibc.tar.zst -f
ls -la /work/out/foyer-$VER-x86_64-glibc.tar.zst
INNER
