# shellcheck shell=sh
# Debian package definitions for foyer-os (built by scripts/build-debs.sh).
# Each package: NAME VERSION ARCH DEPENDS DESCRIPTION, plus a stage_<name> function
# that fills $D (the package root). Builds happen inside debian-env.sh.

FOYER_VER=3.0.0
DEB_REV=1

# runtime deps of the appliance session (trixie + trixie-backports/contrib)
SESSION_DEPS="foyer (>= $FOYER_VER), gamescope, xwayland, hwdata, seatd, udev, libinput10, pipewire, pipewire-pulse, wireplumber, pulseaudio-utils, mesa-vulkan-drivers, libgl1-mesa-dri, dbus, network-manager, bluez, curl, ca-certificates, procps, iproute2"
