#!/bin/sh
# alpine-env.sh — run a command inside a pinned Alpine minirootfs sandboxed
# with bubblewrap. No root, no daemon, no podman/docker: user namespaces only.
#
#   scripts/alpine-env.sh [--root DIR] [--] CMD [ARGS...]
#
# The rootfs lives in .cache/alpine-root (reused; refreshed with apk upgrade).
# The repo is bind-mounted at /work. Inside the sandbox you are "root" (uid 0
# mapped to your user), so apk/abuild work normally.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
. "$HERE/alpine.lock"

ROOT="${ALPINE_ROOT:-$REPO/.cache/alpine-root}"
if [ "${1:-}" = "--root" ]; then ROOT=$2; shift 2; fi
[ "${1:-}" = "--" ] && shift

die() { echo "alpine-env: $*" >&2; exit 1; }
command -v bwrap >/dev/null || die "bubblewrap (bwrap) is required"

fetch_rootfs() {
    tarball="$REPO/.cache/alpine-minirootfs-$ALPINE_VERSION-$ALPINE_ARCH.tar.gz"
    mkdir -p "$REPO/.cache"
    if [ ! -f "$tarball" ]; then
        url="$ALPINE_MIRROR/$ALPINE_BRANCH/releases/$ALPINE_ARCH/alpine-minirootfs-$ALPINE_VERSION-$ALPINE_ARCH.tar.gz"
        echo "alpine-env: downloading $url" >&2
        curl -fL --retry 3 -o "$tarball.part" "$url"
        mv "$tarball.part" "$tarball"
    fi
    echo "$ALPINE_MINIROOTFS_SHA256  $tarball" | sha256sum -c - >/dev/null \
        || { rm -f "$tarball"; die "sha256 mismatch for $tarball (deleted; retry)"; }
    rm -rf "$ROOT.tmp" && mkdir -p "$ROOT.tmp"
    tar -xzf "$tarball" -C "$ROOT.tmp" --no-same-owner --exclude='dev/*'
    printf '%s/%s/main\n%s/%s/community\n' "$ALPINE_MIRROR" "$ALPINE_BRANCH" "$ALPINE_MIRROR" "$ALPINE_BRANCH" \
        > "$ROOT.tmp/etc/apk/repositories"
    # Single-uid user namespace: apk can't apply foreign owners or setuid
    # bits (e.g. linux-pam's unix_chkpwd), marks the package as having a
    # file error and then fails every later `apk add` with "1 error". Wrap
    # apk to clear those stale flags afterwards (the files are installed).
    mv "$ROOT.tmp/sbin/apk" "$ROOT.tmp/sbin/apk.real"
    cat > "$ROOT.tmp/sbin/apk" <<'WRAP'
#!/bin/sh
/sbin/apk.real "$@"
rc=$?
db=/lib/apk/db/installed
if grep -q '^f:f$' "$db" 2>/dev/null; then
    sed -i '/^f:f$/d' "$db"
    # an "N error(s)" exit caused only by unsettable ownership is success
    [ $rc -le 3 ] && rc=0
fi
exit $rc
WRAP
    chmod 755 "$ROOT.tmp/sbin/apk"
    # abuild builds as root inside the namespace: allow it explicitly
    mkdir -p "$ROOT.tmp/root/.abuild"
    echo "$ALPINE_VERSION-2" > "$ROOT.tmp/.foyer-alpine-version"
    rm -rf "$ROOT" && mv "$ROOT.tmp" "$ROOT"
}

if [ ! -f "$ROOT/.foyer-alpine-version" ] || [ "$(cat "$ROOT/.foyer-alpine-version")" != "$ALPINE_VERSION-2" ]; then
    fetch_rootfs
fi

RESOLV=/etc/resolv.conf
[ -r "$RESOLV" ] || RESOLV=/dev/null

exec bwrap \
    --bind "$ROOT" / \
    --bind "$REPO" /work \
    --dev /dev \
    --dev-bind-try /dev/kvm /dev/kvm \
    --proc /proc \
    --tmpfs /tmp \
    --ro-bind "$RESOLV" /etc/resolv.conf \
    --unshare-user --uid 0 --gid 0 \
    --cap-add CAP_SYS_CHROOT --cap-add CAP_CHOWN --cap-add CAP_FOWNER --cap-add CAP_DAC_OVERRIDE --cap-add CAP_SETFCAP \
    --unshare-pid --unshare-ipc --unshare-uts --hostname foyer-build \
    --die-with-parent \
    --setenv HOME /root --setenv PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    --setenv TERM "${TERM:-dumb}" \
    --chdir /work \
    "$@"
