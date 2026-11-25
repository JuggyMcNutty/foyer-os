#!/bin/sh
# boot-test.sh — boot a foyer-os image in QEMU (TCG; KVM if available) and
# wait for the session to come up. Runs in the Alpine tools sandbox.
#
#   scripts/boot-test.sh IMAGE [bios|uefi] [TIMEOUT_S]
#
# Passes when the serial console shows a login prompt (system up, sshd/getty
# running) and, if FOYER_EXPECT_UI=1, gamescope/foyer output from the session.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
IMG=$1; FW=${2:-bios}; TMO=${3:-600}
case "$IMG" in /*) ;; *) IMG="$PWD/$IMG" ;; esac
REL=${IMG#"$REPO"/}
export ALPINE_ROOT="${ALPINE_ROOT:-$REPO/.cache/alpine-imgtools}"
KVM=""; [ -w /dev/kvm ] && KVM=1
exec "$HERE/alpine-env.sh" env REL="$REL" FW="$FW" TMO="$TMO" KVM="$KVM" FOYER_EXPECT_UI="${FOYER_EXPECT_UI:-0}" /bin/sh -eu -s <<'INNER'
apk add -q --no-progress qemu-system-x86_64 qemu-hw-display-virtio-vga qemu-hw-display-virtio-gpu qemu-hw-display-virtio-gpu-pci ovmf
cp "/work/$REL" /tmp/disk.img   # don't mutate the release image
ACCEL="-accel tcg"; [ -n "$KVM" ] && [ -e /dev/kvm ] && ACCEL="-accel kvm -cpu host"
BIOS=""; [ "$FW" = uefi ] && BIOS="-bios /usr/share/ovmf/bios.bin"
LOG=/work/out/boot-$FW.log
: > "$LOG"
qemu-system-x86_64 $ACCEL -m 2048 -smp 2 $BIOS \
    -drive file=/tmp/disk.img,format=raw,if=virtio \
    -device virtio-vga -display none \
    -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
    -serial file:"$LOG" -no-reboot &
QPID=$!
i=0; ok=0
while [ $i -lt "$TMO" ]; do
    if grep -q "login:" "$LOG" 2>/dev/null; then
        if [ "${FOYER_EXPECT_UI:-0}" != 1 ] || grep -qE "Foyer [0-9.]+ ready" "$LOG"; then ok=1; break; fi
    fi
    kill -0 $QPID 2>/dev/null || break
    sleep 2; i=$((i+2))
done
kill $QPID 2>/dev/null || true
tail -25 "$LOG"
[ $ok = 1 ] && { echo "BOOT-TEST $FW: PASS (login prompt after ${i}s)"; exit 0; }
echo "BOOT-TEST $FW: FAIL"; exit 1
INNER
