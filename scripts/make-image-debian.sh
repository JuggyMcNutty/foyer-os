#!/bin/sh
# make-image-debian.sh — foyer-os disk image on a Debian (glibc, systemd) base.
# Same rootless approach and disk layout as make-image.sh (Alpine):
#   GPT: p1 ESP (FAT32, kernel + initrd + systemd-boot / syslinux), p2 ext4 root
#
#   scripts/make-image-debian.sh PROFILE [--ssh-key FILE] [--out DIR]
#
# Steps: (1) debootstrap the target rootfs + profile packages + foyer .debs
# inside the Debian sandbox (nochown preload), (2) assemble the image in the
# Alpine tools sandbox (mkfs.ext4 -d, mtools, sfdisk, syslinux, debugfs).
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
. "$HERE/lib-profile.sh"

[ $# -ge 1 ] || { sed -n '2,12p' "$0"; exit 2; }
load_profile "$1"; shift
SSH_KEY="${FOYER_SSH_PUBKEY:-}"
OUTDIR="$REPO/out"
while [ $# -gt 0 ]; do
    case "$1" in
        --ssh-key) SSH_KEY=$(cat "$2"); shift 2 ;;
        --out) OUTDIR=$2; shift 2 ;;
        *) echo "unknown option $1" >&2; exit 2 ;;
    esac
done
[ "$BASE" = debian ] || { echo "profile $PROFILE_NAME is BASE=$BASE (use make-image.sh)" >&2; exit 1; }
DEBS="$REPO/out/debs/$SUITE"
ls "$DEBS"/foyer_*.deb >/dev/null 2>&1 || { echo "no foyer .debs in $DEBS (run scripts/build-debs.sh)" >&2; exit 1; }
VERSION=$(git -C "$REPO" describe --tags --always 2>/dev/null || echo dev)
PKGS=$(profile_pkgs)
mkdir -p "$OUTDIR"
profile_session_conf > "$OUTDIR/.session.conf"
printf '%s\n' "$SSH_KEY" > "$OUTDIR/.authorized_keys"
OUTREL=${OUTDIR#"$REPO"/}
ROOTREL=.cache/rootfs-$PROFILE_NAME

echo "==> [1/2] rootfs ($SUITE): $PKGS"
"$HERE/debian-env.sh" --suite "$SUITE" env PKGS="$PKGS" SUITE="$SUITE" ROOTREL="$ROOTREL" OUTREL="$OUTREL" \
    HOSTNAME_="$HOSTNAME" PROFILE_NAME="$PROFILE_NAME" VERSION="$VERSION" /bin/sh -eu -s <<'INNER'
apt-get update -qq
apt-get install -y -qq debootstrap >/dev/null
R=/work/$ROOTREL
rm -rf "$R"
# Bootstrap a minimal target (two stages so the chown shim is in place for
# maintainer scripts), then chroot-install the profile packages.
mkdir -p /tmp/shim
printf '#!/bin/sh\nexec /usr/bin/tar --no-same-owner "$@"\n' > /tmp/shim/tar; chmod +x /tmp/shim/tar
PATH=/tmp/shim:$PATH container=mmdebstrap-unshare debootstrap --foreign --variant=minbase \
    --components=main,contrib,non-free,non-free-firmware --include=ca-certificates \
    "$SUITE" "$R" http://deb.debian.org/debian > /tmp/debootstrap.log 2>&1 || { tail -20 /tmp/debootstrap.log; exit 1; }
mkdir -p "$R/usr/local/lib" && cp /usr/local/lib/nochown.so "$R/usr/local/lib/"
chroot "$R" /bin/sh -c 'LD_PRELOAD=/usr/local/lib/nochown.so container=mmdebstrap-unshare /debootstrap/debootstrap --second-stage' \
    > /tmp/debootstrap2.log 2>&1 || { tail -20 /tmp/debootstrap2.log; tail -20 "$R/debootstrap/debootstrap.log" 2>/dev/null; exit 1; }
cat > "$R/etc/apt/sources.list" <<SRC
deb http://deb.debian.org/debian $SUITE main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $SUITE-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $SUITE-backports main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security $SUITE-security main contrib non-free non-free-firmware
SRC
cp /etc/apt/apt.conf.d/99foyer "$R/etc/apt/apt.conf.d/"
printf 'path-exclude /usr/share/doc/*\npath-include /usr/share/doc/*/copyright\npath-exclude /usr/share/man/*\n' > "$R/etc/dpkg/dpkg.cfg.d/01foyer"
# kernel postinst: generic initramfs (not host-only), no bootloader hooks
mkdir -p "$R/etc/initramfs-tools/conf.d"
echo 'MODULES=most' > "$R/etc/initramfs-tools/conf.d/foyer"
echo 'do_symlinks = no' > "$R/etc/kernel-img.conf"
mkdir -p "$R/work" && cp -r /work/out/debs/$SUITE "$R/tmp/debs"
chroot "$R" /bin/sh -eu -c "
    export LD_PRELOAD=/usr/local/lib/nochown.so DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq $PKGS >/dev/null
    # gamescope only exists in backports; let its deps (pipewire libs etc.)
    # come from backports too, in one transaction, so the solver stays consistent
    apt-get install -y -qq -t $SUITE-backports gamescope pipewire pipewire-pulse wireplumber /tmp/debs/*.deb >/dev/null
    apt-get clean
"
rm -rf "$R/tmp/debs" "$R/work"
echo "$HOSTNAME_" > "$R/etc/hostname"
printf '127.0.0.1\tlocalhost %s\n::1\tlocalhost\n' "$HOSTNAME_" > "$R/etc/hosts"
cat > "$R/etc/fstab" <<FSTAB
LABEL=foyer-root /     ext4 rw,relatime 0 1
LABEL=FOYER-ESP  /boot/efi vfat rw,relatime,fmask=0022,dmask=0022 0 2
FSTAB
mkdir -p "$R/boot/efi" "$R/root/.ssh"
cp "/work/$OUTREL/.authorized_keys" "$R/root/.ssh/authorized_keys"
chmod 700 "$R/root/.ssh"; chmod 600 "$R/root/.ssh/authorized_keys"
cp "/work/$OUTREL/.session.conf" "$R/etc/foyer/session.conf"
echo "$PROFILE_NAME" > "$R/etc/foyer/profile"; echo "$VERSION" > "$R/etc/foyer/release"
echo 'PermitRootLogin prohibit-password' > "$R/etc/ssh/sshd_config.d/foyer.conf"
# services: our session on tty1 instead of getty; NM for networking
ln -sf /usr/lib/systemd/system/foyer-session.service "$R/etc/systemd/system/multi-user.target.wants/foyer-session.service"
ln -sf /dev/null "$R/etc/systemd/system/getty@tty1.service"
mkdir -p "$R/etc/systemd/system/multi-user.target.wants"
for s in NetworkManager ssh systemd-timesyncd seatd; do
    f=$(ls "$R"/usr/lib/systemd/system/$s.service 2>/dev/null | head -1)
    [ -n "$f" ] && ln -sf "/usr/lib/systemd/system/$s.service" "$R/etc/systemd/system/multi-user.target.wants/$s.service"
done
case "$PROFILE_NAME" in qemu*)
    mkdir -p "$R/etc/systemd/system/getty.target.wants" "$R/etc/systemd/system/foyer-session.service.d"
    ln -sf /usr/lib/systemd/system/serial-getty@.service "$R/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service"
    # boot test: mirror the session's output to the serial console
    printf '[Service]\nEnvironment=FOYER_LOG_STDERR=info\nStandardOutput=tty\nStandardError=tty\nTTYPath=/dev/ttyS0\nStandardInput=null\n' \
        > "$R/etc/systemd/system/foyer-session.service.d/serial.conf"
    ;;
esac
# machine-id + SSH host keys are per-device: generated on first boot
: > "$R/etc/machine-id"
rm -f "$R"/etc/ssh/ssh_host_*
mkdir -p "$R/etc/systemd/system/ssh.service.d"
printf '[Service]\nExecStartPre=\nExecStartPre=/usr/bin/ssh-keygen -A\nExecStartPre=/usr/sbin/sshd -t\n' > "$R/etc/systemd/system/ssh.service.d/foyer-hostkeys.conf"
# udev hwdb couldn't be compiled in the sandbox; build it on first boot
mkdir -p "$R/etc/systemd/system/systemd-hwdb-update.service.d"
printf '[Unit]\nConditionNeedsUpdate=\nConditionPathExists=!/usr/lib/udev/hwdb.bin\n' > "$R/etc/systemd/system/systemd-hwdb-update.service.d/foyer.conf"
# keep the nochown shim out of the shipped system
rm -f "$R/usr/local/lib/nochown.so" "$R/etc/apt/apt.conf.d/99foyer"
INNER

echo "==> [2/2] image"
export ALPINE_ROOT="${ALPINE_ROOT:-$REPO/.cache/alpine-imgtools}"
exec "$HERE/alpine-env.sh" env PROFILE_NAME="$PROFILE_NAME" BOOT="$BOOT" IMG_SIZE="$IMG_SIZE" VERSION="$VERSION" \
    ROOTREL="$ROOTREL" OUTREL="$OUTREL" /bin/sh -eu -s <<'INNER'
apk add -q --no-progress syslinux mtools dosfstools e2fsprogs e2fsprogs-extra sfdisk zstd
R=/work/$ROOTREL; OUT=/work/$OUTREL; ESP=/tmp/esp
rm -rf "$ESP"; mkdir -p "$ESP"
K=$(ls "$R"/boot/vmlinuz-* | sort -V | tail -1); I=$(ls "$R"/boot/initrd.img-* | sort -V | tail -1)
cp "$K" "$ESP/vmlinuz"; cp "$I" "$ESP/initrd.img"
CMDLINE="root=LABEL=foyer-root rootfstype=ext4 rw quiet loglevel=3 console=tty0"
case "$PROFILE_NAME" in qemu*) CMDLINE="$CMDLINE console=ttyS0,115200" ;; esac
if [ "$BOOT" != bios ]; then
    mkdir -p "$ESP/EFI/BOOT" "$ESP/loader/entries"
    cp "$R/usr/lib/systemd/boot/efi/systemd-bootx64.efi" "$ESP/EFI/BOOT/BOOTX64.EFI"
    printf 'default foyer.conf\ntimeout 0\n' > "$ESP/loader/loader.conf"
    printf 'title foyer-os (%s)\nlinux /vmlinuz\ninitrd /initrd.img\noptions %s\n' "$PROFILE_NAME" "$CMDLINE" > "$ESP/loader/entries/foyer.conf"
fi
if [ "$BOOT" != uefi ]; then
    mkdir -p "$ESP/syslinux"
    cp /usr/share/syslinux/ldlinux.c32 /usr/share/syslinux/libcom32.c32 /usr/share/syslinux/libutil.c32 "$ESP/syslinux/"
    printf 'DEFAULT foyer\nTIMEOUT 0\nPROMPT 0\nLABEL foyer\n  LINUX /vmlinuz\n  INITRD /initrd.img\n  APPEND %s\n' "$CMDLINE" > "$ESP/syslinux/syslinux.cfg"
fi
IMG="$OUT/foyer-os-$PROFILE_NAME-$VERSION.img"
ESP_MB=256; SZ=${IMG_SIZE%G}; TOTAL_MB=$((SZ * 1024)); ROOT_MB=$((TOTAL_MB - ESP_MB - 2))
rm -f "$IMG"; truncate -s "${TOTAL_MB}M" "$IMG"
sfdisk -q "$IMG" <<PT
label: gpt
first-lba: 2048
start=2048, size=$((ESP_MB * 2048)), type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="ESP", attrs="LegacyBIOSBootable"
start=$((2048 + ESP_MB * 2048)), size=$((ROOT_MB * 2048)), type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="foyer-root"
PT
rm -f /tmp/esp.img; truncate -s "${ESP_MB}M" /tmp/esp.img
mkfs.vfat -F 32 -n FOYER-ESP /tmp/esp.img >/dev/null
( cd "$ESP" && find . -mindepth 1 -type d | sed 's|^\./||' | while read -r d; do mmd -i /tmp/esp.img "::$d"; done
  find . -type f | sed 's|^\./||' | while read -r f; do mcopy -i /tmp/esp.img "$f" "::$f"; done )
[ "$BOOT" != uefi ] && syslinux --install --directory /syslinux /tmp/esp.img
rm -f /tmp/root.img
mkfs.ext4 -q -F -L foyer-root -d "$R" -E root_owner=0:0 /tmp/root.img "${ROOT_MB}M"
# restore group ownership/setuid bits the namespace couldn't apply
{
    for f in /etc/shadow /etc/gshadow; do
        g=$(awk -F: '$1=="shadow"{print $3}' "$R/etc/group"); [ -e "$R$f" ] && echo "sif $f gid $g"
    done
    for f in /usr/bin/sudo /usr/bin/passwd /usr/bin/su /usr/bin/mount /usr/bin/umount /usr/bin/newgrp /usr/bin/chfn /usr/bin/chsh /usr/bin/gpasswd; do
        [ -e "$R$f" ] && echo "sif $f mode 0104755"
    done
    g=$(awk -F: '$1=="messagebus"{print $3}' "$R/etc/group")
    [ -n "$g" ] && [ -e "$R/usr/lib/dbus-1.0/dbus-daemon-launch-helper" ] && echo "sif /usr/lib/dbus-1.0/dbus-daemon-launch-helper gid $g" && echo "sif /usr/lib/dbus-1.0/dbus-daemon-launch-helper mode 0104754"
} > /tmp/fix.debugfs
debugfs -w -f /tmp/fix.debugfs /tmp/root.img >/dev/null 2>&1 || true
dd if=/tmp/esp.img of="$IMG" bs=1M seek=1 conv=notrunc status=none
dd if=/tmp/root.img of="$IMG" bs=1M seek=$((1 + ESP_MB)) conv=notrunc status=none
[ "$BOOT" != uefi ] && dd if=/usr/share/syslinux/gptmbr.bin of="$IMG" bs=440 count=1 conv=notrunc status=none
rm -f /tmp/esp.img /tmp/root.img "$OUT/.session.conf" "$OUT/.authorized_keys"
zstd -q -T0 -10 -f "$IMG" -o "$IMG.zst"
ls -la "$IMG" "$IMG.zst"
INNER
