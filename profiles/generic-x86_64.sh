# Template for a modern x86_64 mini-PC (e.g. Intel N100/N150, Ryzen APU) driving
# a 4K TV over HDMI 2.0. Copy to profiles/<device>.sh and adjust.
PROFILE_TITLE="Generic x86_64 4K box"
BASE=alpine
ARCH=x86_64
HOSTNAME=foyer
KERNEL=kernel-lts
FIRMWARE="firmware-intel firmware-rtl firmware-wifi"
GPU=gpu-intel                # gpu-amd for Ryzen
NET="net-ethernet net-wifi"
WIFI=yes
BT=yes
BOOT=uefi                    # both = UEFI + legacy BIOS
DISK=nvme0n1
IMG_SIZE=8G
RENDER_MAX=native            # render the UI at the TV's mode (4K)
ASSET_BUDGET_MB=256
SWAP_MB=0
APPS="jellyfin youtube amazon twitch iptv"
EXTRA_PKGS="apps-browser apps-media bt"
