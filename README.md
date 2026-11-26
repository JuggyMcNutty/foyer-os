# foyer-os

A reproducible living-room appliance: **Alpine Linux (musl) or Debian (glibc)
+ gamescope + PipeWire + the [Foyer](https://github.com/JuggyMcNutty/foyer)
big-picture launcher**, built for a specific device from a **profile**.

- **Rootless builds.** Everything builds inside a pinned distro rootfs sandboxed
  with bubblewrap. There is no podman/docker, no root, no daemon, and nothing
  is compiled on the device.
- **Packages** are APKs (`.deb`s for the Debian base) attached to GitHub
  releases. Devices install them with `apk add --allow-untrusted` and update
  with `foyer-update`.
- **Images** are flashable GPT disk images (UEFI with systemd-boot, legacy BIOS
  with syslinux), assembled with `mkfs.ext4 -d` plus mtools. No loop devices or
  mounts are used. Every release is boot-tested in QEMU.

## Layout

| Path | What |
|---|---|
| `foyer/` | The launcher (git submodule, `JuggyMcNutty/foyer`) |
| `session/` | `session.sh` (tty1 → PipeWire + gamescope + Foyer), `foyer-ctl` (system control backend), `foyer-app` (app wrappers), `foyer-update`, default URLs |
| `aports/` | APKBUILDs: `foyer`, `foyer-session`, `foyer-update`, `foyer-sdl3_image`, `foyer-red`, `foyer-jellyfin-desktop` |
| `profiles/` | Device profiles (`geobook-240`, `ideapad-120s`, `generic-x86_64`, `qemu`) + `base/<distro>.pkgs` logical→package maps |
| `scripts/` | `alpine-env.sh`, `build-apks.sh`, `make-image.sh`, `provision.sh`, `boot-test.sh` (+ Debian equivalents) |
| `.github/workflows/release.yml` | CI: APKs → images per profile → QEMU boot test → release on `v*` tags |

## Quick start

Requirements on the build machine: `bubblewrap`, `curl`, `git`, unprivileged
user namespaces. Any distro works, including a distrobox.

```sh
git clone --recursive https://github.com/JuggyMcNutty/foyer-os && cd foyer-os

scripts/build-apks.sh                              # -> out/apks/x86_64/*.apk
scripts/make-image.sh generic-x86_64 --ssh-key ~/.ssh/id_ed25519.pub
                                                   # -> out/foyer-os-generic-x86_64-<ver>.img(.zst)
scripts/boot-test.sh out/foyer-os-qemu-*.img uefi  # QEMU smoke test (after make-image.sh qemu)

# flash
zstd -dc out/foyer-os-generic-x86_64-*.img.zst | sudo dd of=/dev/sdX bs=4M conv=fsync

# or turn an existing stock Alpine install into foyer-os over SSH
scripts/provision.sh geobook-240 root@192.168.1.123
scripts/provision.sh geobook-240 root@box --release v3.0.0    # from a GitHub release
```

## Device profiles

A profile is a sourced shell file. The key fields are:

```sh
BASE=alpine            # alpine | debian
ARCH=x86_64
KERNEL=kernel-lts      # logical names, mapped per base in profiles/base/*.pkgs
FIRMWARE="firmware-intel firmware-rtl"
GPU=gpu-intel          # gpu-intel | gpu-amd | gpu-generic
NET="net-ethernet"     WIFI=no  BT=no
BOOT=uefi              # uefi | bios | both
IMG_SIZE=6G            # grows to the disk on first boot
RENDER_MAX=1920x1080   # cap UI/app render size (gamescope upscales); "native" for 4K boxes
ASSET_BUDGET_MB=64     # Foyer's texture cache budget
```

For a new board, copy `profiles/generic-x86_64.sh`.

## On the device

| | |
|---|---|
| Config | `/etc/foyer/` — `settings.toml`, `layout.toml`, `apps.d/*.toml`, `themes/<name>/`, `art/`, `session.conf` |
| Session | `/usr/lib/foyer/session.sh` on tty1 (OpenRC `inittab`) |
| Logs | `/var/lib/foyer/state/foyer/foyer.log`, per-app logs in `.../apps/` |
| Control | `foyer-ctl {audio,display,net,wifi,bt,sys,power} ...` |
| Update | `foyer-update [--check] [TAG]` |
| Restart UI | `kill -9 $(pidof gamescope-wl)` (init respawns the session) |

## License

Scripts and packaging: MIT. Bundled software keeps its own license (see each
APKBUILD).
