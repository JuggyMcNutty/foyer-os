#!/bin/sh
# debian-env.sh — run a command inside a Debian rootfs (bookworm by default)
# sandboxed with bubblewrap. Rootless: the rootfs is created with debootstrap
# running inside the Alpine sandbox (scripts/alpine-env.sh), so nothing is
# installed on the build machine.
#
#   scripts/debian-env.sh [--suite bookworm|trixie] [--] CMD [ARGS...]
#
# Single-uid user namespace: package ownership can't be applied, so dpkg/tar
# run with --no-same-owner semantics (fine for build roots; images fix owners
# when the filesystem image is written).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
SUITE=${DEBIAN_SUITE:-bookworm}
if [ "${1:-}" = "--suite" ]; then SUITE=$2; shift 2; fi
[ "${1:-}" = "--" ] && shift
MIRROR=${DEBIAN_MIRROR:-http://deb.debian.org/debian}
ROOT="$REPO/.cache/debian-$SUITE"

if [ ! -f "$ROOT/.foyer-debian" ]; then
    echo "debian-env: bootstrapping $SUITE rootfs (once)" >&2
    ALPINE_ROOT="$REPO/.cache/alpine-imgtools" "$HERE/alpine-env.sh" env SUITE="$SUITE" MIRROR="$MIRROR" /bin/sh -eu -s <<'INNER'
apk add -q --no-progress debootstrap perl tar dpkg debian-archive-keyring
# tar shim: never try to chown (single-uid namespace)
mkdir -p /tmp/shim
printf '#!/bin/sh\nexec /bin/tar.real --no-same-owner --no-same-permissions "$@"\n' > /tmp/shim/tar
[ -e /bin/tar.real ] || cp /bin/tar /bin/tar.real
chmod +x /tmp/shim/tar
T=/work/.cache/debian-$SUITE
rm -rf "$T.tmp"
# Stage 1 only (download + extract); stage 2 runs inside the Debian root.
PATH=/tmp/shim:$PATH container=mmdebstrap-unshare \
    debootstrap --foreign --variant=minbase --include=ca-certificates,apt-utils "$SUITE" "$T.tmp" "$MIRROR"
rm -rf "$T" && mv "$T.tmp" "$T"
INNER
    # Stage 2: configure inside the new root with the nochown shim preloaded
    # (built with the host C compiler; plain glibc, works on bookworm+).
    mkdir -p "$ROOT/usr/local/lib"
    cc -shared -fPIC -O2 -o "$ROOT/usr/local/lib/nochown.so" "$HERE/lib/nochown.c" -ldl
    bwrap --bind "$ROOT" / --dev /dev --proc /proc --tmpfs /tmp \
        --ro-bind /etc/resolv.conf /etc/resolv.conf \
        --unshare-user --uid 0 --gid 0 --cap-add CAP_SYS_CHROOT --cap-add CAP_CHOWN --cap-add CAP_FOWNER \
        --cap-add CAP_DAC_OVERRIDE --cap-add CAP_SETFCAP --unshare-pid --die-with-parent \
        --setenv PATH /usr/sbin:/usr/bin:/sbin:/bin --setenv DEBIAN_FRONTEND noninteractive \
        --setenv LD_PRELOAD /usr/local/lib/nochown.so \
        /bin/sh -c 'container=mmdebstrap-unshare /debootstrap/debootstrap --second-stage'
    printf 'deb %s %s main\n' "$MIRROR" "$SUITE" > "$ROOT/etc/apt/sources.list"
    # apt: no privilege drop (single-uid namespace), quiet, minimal
    mkdir -p "$ROOT/etc/apt/apt.conf.d" "$ROOT/etc/dpkg/dpkg.cfg.d"
    printf 'APT::Sandbox::User "root";\nAcquire::Retries "3";\nAPT::Install-Recommends "false";\n' > "$ROOT/etc/apt/apt.conf.d/99foyer"
    printf 'force-unsafe-io\npath-exclude /usr/share/doc/*\npath-exclude /usr/share/man/*\n' > "$ROOT/etc/dpkg/dpkg.cfg.d/01foyer"
    echo "$SUITE" > "$ROOT/.foyer-debian"
fi

RESOLV=/etc/resolv.conf
[ -r "$RESOLV" ] || RESOLV=/dev/null
exec bwrap \
    --bind "$ROOT" / \
    --bind "$REPO" /work \
    --dev /dev \
    --proc /proc \
    --tmpfs /tmp \
    --ro-bind "$RESOLV" /etc/resolv.conf \
    --unshare-user --uid 0 --gid 0 \
    --cap-add CAP_SYS_CHROOT --cap-add CAP_CHOWN --cap-add CAP_FOWNER --cap-add CAP_DAC_OVERRIDE --cap-add CAP_SETFCAP \
    --unshare-pid --unshare-ipc --unshare-uts --hostname foyer-build \
    --die-with-parent \
    --setenv HOME /root --setenv PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    --setenv DEBIAN_FRONTEND noninteractive \
    --setenv LD_PRELOAD /usr/local/lib/nochown.so \
    --setenv TERM "${TERM:-dumb}" --setenv LC_ALL C.UTF-8 \
    --chdir /work \
    "$@"
