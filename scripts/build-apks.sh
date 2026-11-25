#!/bin/sh
# build-apks.sh — build foyer-os APKs with abuild inside the Alpine bwrap
# sandbox (scripts/alpine-env.sh). Output: out/apks/<arch>/*.apk (+ APKINDEX).
#
#   scripts/build-apks.sh [PKG...]     default: all, in dependency order
#   FOYER_JOBS=N                       parallel make jobs (default: nproc)
#
# APKs are signed with a throwaway key (abuild requires a signature on the
# index); devices install them with `apk add --allow-untrusted`.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
ORDER="foyer-sdl3_image foyer foyer-session foyer-update foyer-red foyer-jellyfin-desktop"
PKGS="${*:-$ORDER}"

[ -f "$REPO/foyer/CMakeLists.txt" ] || { echo "build-apks: foyer/ submodule missing (git submodule update --init)" >&2; exit 1; }

exec "$HERE/alpine-env.sh" /bin/sh -s${FOYER_TRACE:+x} -- $PKGS <<'INNER'
set -eu
JOBS=${FOYER_JOBS:-$(nproc)}
apk update -q
apk add -q --no-progress alpine-sdk
# abuild refuses to run as root unless forced; we are a mapped user anyway.
export ABUILD_USERDIR=/root/.abuild
mkdir -p "$ABUILD_USERDIR"
if [ ! -f "$ABUILD_USERDIR/abuild.conf" ]; then
    abuild-keygen -a -n -q >/dev/null 2>&1 || abuild-keygen -a -n
fi
cp -n "$ABUILD_USERDIR"/*.rsa.pub /etc/apk/keys/ 2>/dev/null || true
export JOBS MAKEFLAGS="-j$JOBS" SAMUFLAGS="-j$JOBS"
export REPODEST=/work/out/apks-repo
export SRCDEST=/work/.cache/distfiles
export FOYER_SRC=/work/foyer FOYER_OS_SRC=/work
mkdir -p "$REPODEST" "$SRCDEST"
# local repo first so later packages can depend on earlier ones
grep -q "$REPODEST/aports" /etc/apk/repositories || sed -i "1i $REPODEST/aports" /etc/apk/repositories
for p in "$@"; do
    echo "==> $p"
    cd /work/aports/$p
    rm -rf src pkg
    abuild -F checksum >/dev/null 2>&1 || true
    # noarch packages have no build step: skip installing their runtime
    # depends (e.g. gamescope, mesa) into the build root
    if grep -q '^arch="noarch"' APKBUILD; then abuild -F -d -r; else abuild -F -r; fi
    rm -rf src pkg
done
ARCH=$(apk --print-arch)
mkdir -p /work/out/apks/$ARCH
cp -f "$REPODEST"/aports/$ARCH/*.apk /work/out/apks/$ARCH/
ls -la /work/out/apks/$ARCH/
INNER
