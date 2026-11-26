# GEOMARK Geobook 240 motherboard (14" 2-in-1) in a mini-PC case — replaces
# the ideapad 120S.
# Intel Pentium Silver N5030 (Gemini Lake, UHD 605, 4 cores/4 threads), 8 GB RAM.
# Boot disk lives in a USB dock (external); the board's UEFI must boot USB
# mass storage. HDMI version unverified — check the EDID/VSDB on first boot.
PROFILE_TITLE="geobook 240 (N5030, 8 GB)"
BASE=alpine
ARCH=x86_64
HOSTNAME=streamyboi
KERNEL=kernel-lts
# rtl: the ideapad's r8152 USB-C Ethernet adapter is the expected NIC; drop
# it (and add net-wifi/firmware-wifi) if the box runs on Wi-Fi instead.
FIRMWARE="firmware-intel firmware-rtl"
GPU=gpu-intel
NET="net-ethernet"
WIFI=no
BT=no
BOOT=uefi
DISK=sda                     # USB-docked SATA disk
IMG_SIZE=8G                  # image grows to the disk on first boot
# 8 GB RAM + UHD 605: render at the panel's native resolution (the ideapad
# was capped at 1080p for 2 GB RAM / HD 500).
RENDER_MAX=native
# VAAPI: Gemini Lake (Gen 9.5) MUST use the classic i965 driver. The iHD
# media-driver is broken on this GPU just like on Apollo Lake: 4K HEVC 10-bit
# decodes ~38x slower than realtime with iHD (190 s for 5 s of content) vs
# 3.8 s with i965 (~1.3x realtime; software ~1.5x). Measured 2026-11-26.
# Written to /etc/foyer/env.d/libva.conf by make-image.sh / provision.sh.
VA_DRIVER=i965
SWAP_MB=2048
APPS="jellyfin youtube amazon twitch iptv"
EXTRA_PKGS="apps-browser apps-media"
