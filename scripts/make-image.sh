#!/bin/sh
# make-image.sh — build a flashable foyer-os disk image for a device profile.
# Rootless: no loop devices, no mounts, no sudo. Runs in the Alpine bwrap
# sandbox (scripts/alpine-env.sh).
#
#   scripts/make-image.sh PROFILE [--ssh-key FILE] [--out DIR]
#
# Layout (GPT, also bootable on legacy BIOS via gptmbr + syslinux):
#   p1  ESP   FAT32  256 MiB  kernel, initramfs, systemd-boot (UEFI), syslinux (BIOS)
#   p2  root  ext4   rest     Alpine + foyer-os, built with mkfs.ext4 -d
# The root filesystem grows to fill the disk on first boot (foyer-firstboot).
#
# Output: out/foyer-os-<profile>-<version>.img (+ .img.zst)
# Flash:  zstd -dc out/foyer-os-*.img.zst | sudo dd of=/dev/sdX bs=4M conv=fsync
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/.." && pwd)
. "$HERE/lib-profile.sh"
. "$HERE/alpine.lock"

[ $# -ge 1 ] || { sed -n '2,16p' "$0"; exit 2; }
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
[ "$BASE" = alpine ] || { echo "make-image.sh: BASE=$BASE is built by make-image-debian.sh" >&2; exit 1; }
APKS="$REPO/out/apks/$ARCH"
ls "$APKS"/foyer-[0-9]*.apk >/dev/null 2>&1 || { echo "no foyer APKs in $APKS (run scripts/build-apks.sh)" >&2; exit 1; }
VERSION=$(git -C "$REPO" describe --tags --always 2>/dev/null || echo dev)
PKGS=$(profile_pkgs)
mkdir -p "$OUTDIR"
profile_session_conf > "$OUTDIR/.session.conf"
printf '%s\n' "$SSH_KEY" > "$OUTDIR/.authorized_keys"

# Separate tools rootfs so image builds don't contend with package builds.
export ALPINE_ROOT="${ALPINE_ROOT:-$REPO/.cache/alpine-imgtools}"
exec "$HERE/alpine-env.sh" env \
    PROFILE_NAME="$PROFILE_NAME" PKGS="$PKGS" ARCH="$ARCH" BOOT="$BOOT" DISK="$DISK" IMG_SIZE="$IMG_SIZE" \
    HOSTNAME_="$HOSTNAME" SWAP_MB="$SWAP_MB" VERSION="$VERSION" ASSET_BUDGET_MB="$ASSET_BUDGET_MB" \
    VA_DRIVER="$VA_DRIVER" \
    ALPINE_BRANCH="$ALPINE_BRANCH" ALPINE_MIRROR="$ALPINE_MIRROR" KERNEL_FLAVOR="$(case $KERNEL in kernel-virt) echo virt;; *) echo lts;; esac)" \
    OUTREL="${OUTDIR#"$REPO"/}" \
    /bin/sh -eu -s <<'INNER'
cd /work
apk update -q
apk add -q --no-progress syslinux mtools dosfstools e2fsprogs sfdisk zstd
OUT=/work/$OUTREL
ROOTFS=/tmp/rootfs
ESP=/tmp/esp
rm -rf "$ROOTFS" "$ESP"; mkdir -p "$ROOTFS" "$ESP"

echo "==> installing rootfs ($PROFILE_NAME): $PKGS"
mkdir -p "$ROOTFS/etc/apk/keys"
cp /etc/apk/keys/* "$ROOTFS/etc/apk/keys/"
printf '%s/%s/main\n%s/%s/community\n' "$ALPINE_MIRROR" "$ALPINE_BRANCH" "$ALPINE_MIRROR" "$ALPINE_BRANCH" > "$ROOTFS/etc/apk/repositories"
# Keep the initramfs generic for the device class, and avoid hostonly detection
# (we are not running on the target).
mkdir -p "$ROOTFS/etc/mkinitfs"
echo 'features="ata base ext4 keymap kms mmc nvme scsi usb virtio"' > "$ROOTFS/etc/mkinitfs/mkinitfs.conf"
# In a single-uid user namespace apk can't chown to other ids (shadow group,
# setuid helpers) and exits non-zero although every file is installed.
# Ownership is corrected when the ext4 image is written (see fix_owners).
apk_root() {
    apk --root "$ROOTFS" --no-progress -q "$@" || true
    sed -i '/^f:f$/d' "$ROOTFS/lib/apk/db/installed"
}
# shellcheck disable=SC2086
apk_root add --initdb --arch "$ARCH" $PKGS
APKS=/work/out/apks/$ARCH
# local .apk files: allowed into world (they'd normally need a cache); later
# updates come from foyer-update (GitHub releases)
apk_root add --allow-untrusted --force-non-repository \
    "$APKS"/foyer-sdl3_image-[0-9]*.apk "$APKS"/foyer-[0-9]*.apk "$APKS"/foyer-session-*.apk "$APKS"/foyer-update-*.apk \
    $(ls "$APKS"/foyer-red-*.apk "$APKS"/foyer-jellyfin-desktop-*.apk 2>/dev/null)
for p in alpine-base linux-$KERNEL_FLAVOR foyer foyer-session; do
    apk --root "$ROOTFS" info -e "$p" >/dev/null || { echo "rootfs: $p failed to install" >&2; exit 1; }
done

echo "==> configuring system"
echo "$HOSTNAME_" > "$ROOTFS/etc/hostname"
printf '127.0.0.1\tlocalhost %s\n::1\tlocalhost\n' "$HOSTNAME_" > "$ROOTFS/etc/hosts"
cat > "$ROOTFS/etc/network/interfaces" <<NET
auto lo
iface lo inet loopback
NET
# DHCP on every wired NIC (names differ per board). USB NICs can enumerate
# after networking starts (a reboot otherwise brings no network), so
# re-check for 60 s in the background.
cat > "$ROOTFS/etc/local.d/foyer-net.start" <<'NET'
#!/bin/sh
setup() {
    changed=0
    for n in /sys/class/net/*; do
        i=${n##*/}
        case "$i" in lo|wl*|docker*|veth*) continue ;; esac
        [ -d "$n/wireless" ] && continue
        if ! grep -q "iface $i" /etc/network/interfaces; then
            printf 'auto %s\niface %s inet dhcp\n' "$i" "$i" >> /etc/network/interfaces
            changed=1
        fi
    done
    [ "$changed" = 1 ] && rc-service networking restart >/dev/null 2>&1
}
setup
( for i in 1 2 3 4 5 6; do sleep 10; setup; done ) >/dev/null 2>&1 &
NET
chmod +x "$ROOTFS/etc/local.d/foyer-net.start"
# first boot: grow root partition + filesystem to the disk
cat > "$ROOTFS/etc/local.d/foyer-firstboot.start" <<'FB'
#!/bin/sh
[ -f /etc/foyer/.firstboot-done ] && exit 0
root=$(awk '$2 == "/" {print $1}' /proc/mounts | head -1)
case "$root" in /dev/*) ;; *) root=$(findfs "$root" 2>/dev/null) ;; esac
disk=/dev/$(lsblk -no pkname "$root" 2>/dev/null)
part=$(cat /sys/class/block/${root##*/}/partition 2>/dev/null)
if [ -b "$disk" ] && [ -n "$part" ]; then
    echo ", +" | sfdisk --no-reread -N "$part" "$disk" >/dev/null 2>&1
    partx -u "$disk" 2>/dev/null
    resize2fs "$root" >/dev/null 2>&1
fi
# swapfile: size chosen by the profile (written at build time), created here
# so the image stays small and any disk size works.
if [ -s /etc/foyer/swap_mb ] && grep -q '^/swapfile' /etc/fstab && [ ! -f /swapfile ]; then
    dd if=/dev/zero of=/swapfile bs=1M count=$(cat /etc/foyer/swap_mb) status=none
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null 2>&1
    swapon /swapfile 2>/dev/null || true
fi
touch /etc/foyer/.firstboot-done
FB
chmod +x "$ROOTFS/etc/local.d/foyer-firstboot.start"
apk_root add sfdisk partx lsblk e2fsprogs-extra
cat > "$ROOTFS/etc/fstab" <<FSTAB
LABEL=foyer-root /     ext4 rw,relatime 0 1
LABEL=FOYER-ESP  /boot vfat rw,relatime,fmask=0022,dmask=0022 0 2
tmpfs            /tmp  tmpfs nosuid,nodev 0 0
FSTAB
if [ "$SWAP_MB" -gt 0 ]; then
    echo "/swapfile none swap sw 0 0" >> "$ROOTFS/etc/fstab"
    echo "$SWAP_MB" > "$ROOTFS/etc/foyer/swap_mb"
fi
# Audio: use the legacy HDA driver, not SOF. The SOF driver claims the
# controller but the image ships no SOF firmware, so it creates no cards
# (measured on geobook-240: no soundcards until forced to legacy HDA).
printf 'options snd-intel-dspcfg dsp_driver=1\n' > "$ROOTFS/etc/modprobe.d/foyer-audio.conf"
# root: key-only SSH; console autologin is the TV session (tty1)
mkdir -p "$ROOTFS/root/.ssh"; chmod 700 "$ROOTFS/root/.ssh"
cp "$OUT/.authorized_keys" "$ROOTFS/root/.ssh/authorized_keys"; chmod 600 "$ROOTFS/root/.ssh/authorized_keys"
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin prohibit-password/' "$ROOTFS/etc/ssh/sshd_config"
rm -f "$ROOTFS"/etc/ssh/ssh_host_*   # generated per device by the sshd init script
# services
for s in devfs dmesg; do ln -sf /etc/init.d/$s "$ROOTFS/etc/runlevels/sysinit/$s"; done
for s in udev udev-trigger udev-settle; do [ -e "$ROOTFS/etc/init.d/$s" ] && ln -sf /etc/init.d/$s "$ROOTFS/etc/runlevels/sysinit/$s"; done
for s in modules sysctl hostname bootmisc syslog hwclock swap; do [ -e "$ROOTFS/etc/init.d/$s" ] && ln -sf /etc/init.d/$s "$ROOTFS/etc/runlevels/boot/$s"; done
for s in networking sshd chronyd local seatd dbus; do [ -e "$ROOTFS/etc/init.d/$s" ] && ln -sf /etc/init.d/$s "$ROOTFS/etc/runlevels/default/$s"; done
for s in mount-ro killprocs savecache; do ln -sf /etc/init.d/$s "$ROOTFS/etc/runlevels/shutdown/$s"; done
# the session package's post-install ran inside apk; make sure tty1 is ours
sed -i 's|^tty1::.*|tty1::respawn:/bin/sh /usr/lib/foyer/session.sh|' "$ROOTFS/etc/inittab"
# VAAPI driver pin (e.g. i965 on Intel Gen 9/9.5, where iHD decodes HEVC
# far too slowly). Sourced by foyer-app on every app launch.
[ -n "$VA_DRIVER" ] && {
    mkdir -p "$ROOTFS/etc/foyer/env.d"
    printf 'export LIBVA_DRIVER_NAME=%s\n' "$VA_DRIVER" > "$ROOTFS/etc/foyer/env.d/libva.conf"
}
cp "$OUT/.session.conf" "$ROOTFS/etc/foyer/session.conf"
echo "$PROFILE_NAME" > "$ROOTFS/etc/foyer/profile"
echo "$VERSION" > "$ROOTFS/etc/foyer/release"
[ -e "$ROOTFS/etc/htpc" ] || ln -s foyer "$ROOTFS/etc/htpc"
mkdir -p "$ROOTFS/boot"

echo "==> boot files"
KVER=$(ls "$ROOTFS/lib/modules" | head -1)
KIMG=$(ls "$ROOTFS"/boot/vmlinuz-* | head -1)
IIMG=$(ls "$ROOTFS"/boot/initramfs-* | head -1)
[ -f "$KIMG" ] && [ -f "$IIMG" ] || { echo "kernel/initramfs missing in rootfs" >&2; exit 1; }
cp "$KIMG" "$ESP/vmlinuz"; cp "$IIMG" "$ESP/initramfs"
for f in "$ROOTFS"/boot/*-ucode.img; do [ -f "$f" ] && cp "$f" "$ESP/"; done
rm -rf "$ROOTFS"/boot/*   # /boot is the ESP at runtime
UCODE=""; for f in "$ESP"/*-ucode.img; do [ -f "$f" ] && UCODE="$UCODE,/$(basename "$f")"; done
CMDLINE="root=LABEL=foyer-root rootfstype=ext4 modules=ext4 quiet loglevel=3 console=tty0"
case "$PROFILE_NAME" in qemu*)
    CMDLINE="$CMDLINE console=ttyS0,115200"
    grep -q '^ttyS0' "$ROOTFS/etc/inittab" || echo 'ttyS0::respawn:/sbin/getty -L 115200 ttyS0 vt100' >> "$ROOTFS/etc/inittab"
    # make session output visible on the serial console for the boot test
    sed -i 's|^tty1::.*|tty1::respawn:/bin/sh -c "FOYER_LOG_STDERR=info /usr/lib/foyer/session.sh 2>\&1 \| tee /dev/ttyS0"|' "$ROOTFS/etc/inittab"
    ;;
esac
# UEFI: systemd-boot as the fallback loader
if [ "$BOOT" != bios ]; then
    mkdir -p "$ESP/EFI/BOOT" "$ESP/loader/entries"
    cp /work/.cache/systemd-bootx64.efi "$ESP/EFI/BOOT/BOOTX64.EFI" 2>/dev/null || {
        apk fetch -q --stdout systemd-boot | tar -xzO usr/lib/systemd/boot/efi/systemd-bootx64.efi > "$ESP/EFI/BOOT/BOOTX64.EFI"
    }
    printf 'default foyer.conf\ntimeout 0\nconsole-mode keep\n' > "$ESP/loader/loader.conf"
    {
        echo "title   foyer-os ($PROFILE_NAME)"
        echo "linux   /vmlinuz"
        for f in "$ESP"/*-ucode.img; do [ -f "$f" ] && echo "initrd  /$(basename "$f")"; done
        echo "initrd  /initramfs"
        echo "options $CMDLINE"
    } > "$ESP/loader/entries/foyer.conf"
fi
# BIOS: syslinux on the FAT ESP (installed after the image is assembled)
if [ "$BOOT" != uefi ]; then
    mkdir -p "$ESP/syslinux"
    cp /usr/share/syslinux/ldlinux.c32 /usr/share/syslinux/libcom32.c32 /usr/share/syslinux/libutil.c32 /usr/share/syslinux/menu.c32 "$ESP/syslinux/"
    cat > "$ESP/syslinux/syslinux.cfg" <<SYS
DEFAULT foyer
TIMEOUT 0
PROMPT 0
LABEL foyer
  LINUX /vmlinuz
  INITRD /initramfs${UCODE}
  APPEND $CMDLINE
SYS
fi

echo "==> assembling image"
IMG="$OUT/foyer-os-$PROFILE_NAME-$VERSION.img"
ESP_MB=256
SZ=$(echo "$IMG_SIZE" | sed 's/G$//')
TOTAL_MB=$((SZ * 1024))
ROOT_MB=$((TOTAL_MB - ESP_MB - 2))
rm -f "$IMG"
truncate -s "${TOTAL_MB}M" "$IMG"
sfdisk -q "$IMG" <<PT
label: gpt
first-lba: 2048
start=2048, size=$((ESP_MB * 2048)), type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="ESP", attrs="LegacyBIOSBootable"
start=$((2048 + ESP_MB * 2048)), size=$((ROOT_MB * 2048)), type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="foyer-root"
PT
# ESP (FAT32) — built in a separate file, then spliced in
rm -f /tmp/esp.img; truncate -s "${ESP_MB}M" /tmp/esp.img
mkfs.vfat -F 32 -n FOYER-ESP /tmp/esp.img >/dev/null
( cd "$ESP" && find . -mindepth 1 -type d | sed 's|^\./||' | while read -r d; do mmd -i /tmp/esp.img "::$d"; done
  find . -type f | sed 's|^\./||' | while read -r f; do mcopy -i /tmp/esp.img "$f" "::$f"; done )
if [ "$BOOT" != uefi ]; then
    syslinux --install --directory /syslinux /tmp/esp.img
fi
# root (ext4 from a directory — no mount)
rm -f /tmp/root.img
mkfs.ext4 -q -F -L foyer-root -d "$ROOTFS" -E root_owner=0:0 /tmp/root.img "${ROOT_MB}M"
# Everything was written as our (mapped) uid 0. Restore the few non-root
# owners / setuid bits apk couldn't set in the namespace.
fix_owners() {
    g_shadow=$(awk -F: '$1=="shadow"{print $3}' "$ROOTFS/etc/group")
    u_chrony=$(awk -F: '$1=="chrony"{print $3}' "$ROOTFS/etc/passwd")
    g_chrony=$(awk -F: '$1=="chrony"{print $4}' "$ROOTFS/etc/group")
    {
        [ -n "$g_shadow" ] && for f in /etc/shadow /etc/shadow-; do
            [ -e "$ROOTFS$f" ] && printf 'sif %s gid %s\nsif %s mode 0100640\n' "$f" "$g_shadow" "$f"
        done
        # chrony runs as its own user and needs to write the drift file;
        # the sandbox apk cannot chown, so it lands root:root in the image.
        [ -n "$u_chrony" ] && [ -e "$ROOTFS/var/lib/chrony" ] && \
            printf 'sif /var/lib/chrony uid %s\nsif /var/lib/chrony gid %s\n' "$u_chrony" "$g_chrony"
        [ -e "$ROOTFS/usr/sbin/unix_chkpwd" ] && printf 'sif /usr/sbin/unix_chkpwd mode 0102755\n'
        [ -e "$ROOTFS/bin/bbsuid" ] && printf 'sif /bin/bbsuid mode 0104755\n'
    } > /tmp/fix.debugfs
    debugfs -w -f /tmp/fix.debugfs /tmp/root.img >/dev/null 2>&1 || true
}
fix_owners
dd if=/tmp/esp.img of="$IMG" bs=1M seek=1 conv=notrunc status=none
dd if=/tmp/root.img of="$IMG" bs=1M seek=$((1 + ESP_MB)) conv=notrunc status=none
if [ "$BOOT" != uefi ]; then
    dd if=/usr/share/syslinux/gptmbr.bin of="$IMG" bs=440 count=1 conv=notrunc status=none
fi
rm -f /tmp/esp.img /tmp/root.img "$OUT/.session.conf" "$OUT/.authorized_keys"
echo "==> compressing"
zstd -q -T0 -10 -f "$IMG" -o "$IMG.zst"
ls -la "$IMG" "$IMG.zst"
echo "kernel $KVER  rootfs $(du -sh "$ROOTFS" | cut -f1)"
INNER
