# Lenovo ideapad 120S-11IAP board in a mini-PC case (the original box).
# Celeron N3350 (Apollo Lake, HD 500), 2 GB RAM, 32 GB eMMC, HDMI 1.4 (1080p60
# link; the TV is 4K so the UI may *output* 4K@30 but renders at 1080p).
PROFILE_TITLE="ideapad 120S (N3350, 2 GB)"
BASE=alpine
ARCH=x86_64
HOSTNAME=streamyboi
KERNEL=kernel-lts
FIRMWARE="firmware-intel firmware-rtl"
GPU=gpu-intel
NET="net-ethernet"          # r8152 USB-C Ethernet; add net-wifi with a dongle
WIFI=no
BT=no
BOOT=uefi
DISK=mmcblk0                 # eMMC
IMG_SIZE=6G                  # image grows to the disk on first boot
# Rendering: keep the UI at 1080p even if the TV accepts 4K (2 GB RAM, HD 500)
RENDER_MAX=1920x1080
ASSET_BUDGET_MB=64
SWAP_MB=512
APPS="jellyfin youtube amazon twitch iptv"
EXTRA_PKGS="apps-browser apps-media"
