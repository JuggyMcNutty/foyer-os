# QEMU test profile, Debian base (CI boot test for the glibc image).
. "$PROFILE_DIR/qemu.sh"
PROFILE_TITLE="QEMU test VM (Debian)"
BASE=debian
SUITE=trixie
KERNEL=kernel-lts            # Debian cloud kernel lacks virtio-gpu DRM
