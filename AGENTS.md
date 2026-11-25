# foyer-os — Project & Handoff

Living document for this repo (**JuggyMcNutty/foyer-os**) and the launcher
submodule (**JuggyMcNutty/foyer**). **Keep "Current state" and "Session log"
updated every session**; future sessions start here.

## Overview

A reproducible living-room appliance:

- **Base:** Alpine 3.24 (musl, OpenRC) today. A Debian (glibc, systemd) base is
  planned for the 4K board (see PLAN.md, Phase E).
- **Compositor:** gamescope. If gamescope can't start (e.g. no DRM-capable
  Vulkan), the session falls back to Foyer on KMS.
- **Audio:** PipeWire, pipewire-pulse and WirePlumber, started inside the
  session. HDMI is chosen by default (`foyer-ctl audio output/restore`).
- **Front door:** **Foyer**, our rewrite of big-launcher. It is C++23/SDL3 with
  its own retained UI engine, Steam Big Picture style, and dp layout from 480p
  to 4K. Kodi is ruled out.
- **Apps:** Jellyfin (jellyfin-desktop), YouTube (Red TV mode), Prime Video and
  Twitch (Chromium kiosk), IPTV (mpv).

Device-specific facts are in **[hardwarefacts.md](hardwarefacts.md)** (current
box: ideapad 120S board, N3350, 2 GB RAM, 32 GB eMMC, HDMI 1.4 to a 4K TV).

## Access

| How | Detail |
|---|---|
| SSH | `ssh htpc` → `root@192.168.1.123`, key auth (password auth still on — temp password, LAN only) |
| GitHub | `gh` is logged in as JuggyMcNutty; repos `foyer` (launcher) and `foyer-os` (this) |

## Repos & branches

- **foyer-os** (this directory): `session/`, `aports/`, `profiles/`, `scripts/`,
  docs, and the `foyer/` submodule.
- **foyer** (`foyer/`): the launcher. Upstream is complexlogic/big-launcher,
  tracked as the `upstream` remote.
- **Only `main`** in both repos. Rollback is done with tags: `v2.0.0` (last
  big-launcher-named build), `archive/htpc-v1` and `upstream-2025-08`.

## How to build / ship

| Task | Command |
|---|---|
| Launcher dev build | `cd foyer && cmake -S . -B build && cmake --build build && ./build/tests/foyer_tests` |
| Launcher UI screenshot (any res) | `FOYER_DATA_DIR=$PWD/data ./build/src/foyer -c /tmp/cfg --size 3840x2160 --screenshot out.png [--open :display] [--keys right,accept]` |
| APKs | `scripts/build-apks.sh [pkg...]` → `out/apks/x86_64/` |
| Provision a box | `scripts/provision.sh ideapad-120s htpc` (only APKs; no on-box compiling) |
| Disk image | `scripts/make-image.sh <profile> --ssh-key ~/.ssh/id_ed25519.pub` |
| QEMU boot test | `FOYER_EXPECT_UI=1 scripts/boot-test.sh out/foyer-os-qemu-*.img {bios,uefi}` |
| Release | push a `v*` tag → GitHub Actions builds APKs + images, boot-tests, attaches to the release |

## Current state

- [x] **Apps launch.** Two root causes are fixed: the init PATH lacked
  `/usr/local/bin`, and Chromium/QtWebEngine refuse to run as root without
  `--no-sandbox`. Failures now show a toast with the reason, and each app has
  its own log.
- [x] **Network page** shows per-interface IP, speed, gateway, DNS and MAC.
- [x] **Foyer v3**: Big-Picture shell, settings (all pages), layout and app
  editors, OSK, quick panel (gamescope overlay), TOML config, themes
  (Midnight / Daylight / OLED plus drop-in), keep/revert for resolution
  changes. Verified on the box.
- [x] **Resolution**: real EDID modes, Automatic (TV preferred), render-size
  cap per profile, 15 s keep/revert with automatic revert in `session.sh`.
- [x] **Build framework**: bwrap Alpine sandbox, 6 APKBUILDs, profiles,
  provision.sh, rootless make-image.sh, QEMU boot test (BIOS + UEFI pass).
  The box was re-provisioned from APKs; `/usr/local` is empty.
- [x] CI: foyer (Alpine and bookworm), foyer-os (APKs → images → boot test →
  release).
- [ ] **TV check by the user**: navigation feel, the overlay over Jellyfin/Red,
  sound.
- [ ] Prime Video DRM (no Widevine on Alpine; the Debian base may fix it).
- [ ] IPTV playlist is still a placeholder.
- [ ] Phase E: Debian/glibc base, `.deb`s, systemd session, NetworkManager
  backend.
- [ ] Apps run as root (sandbox disabled). Move them to an unprivileged user.
- [ ] CEC: no adapter (HD 500 has no CEC). Revisit with a Pulse-Eight USB
  adapter.

## Gotchas (keep these)

- **Box**
  - **OpenRC, ifupdown-ng, musl, no AVX, 2 GB RAM.** eMMC swap is slow; keep
    the resident set small (Foyer ~75 MB, gamescope ~45 MB).
  - **gamescope ignores SIGTERM**: restart the session with
    `kill -9 $(pidof gamescope-wl)`.
  - **`pgrep -f gamescope` matches your own ssh shell.** Use
    `pidof gamescope-wl` or `pgrep -x`.
  - **SDL user events must be registered** (`SDL_RegisterEvents`).
    Hard-coded `0x8000000x` types are silently dropped, which is what made
    v2's job results vanish.
  - **PipeWire must be restarted as a set.** A half-dead set (no wireplumber)
    makes SDL's audio open hang; Foyer now opens audio on a thread.
  - `session.sh` lives in `/usr/lib/foyer/` (package code). Config lives in
    `/etc/foyer/`, and `/etc/htpc` is a compat symlink.
- **Build sandbox**
  - It is a single-uid user namespace. apk can't chown or set setuid bits;
    the `/sbin/apk` wrapper in the sandbox clears the resulting stale error
    flags, and `make-image.sh` restores owners with `debugfs`.
  - Images need `CAP_SYS_CHROOT` inside the namespace (for apk scripts),
    which `alpine-env.sh` grants.
- **Dev machine** (Arch distrobox)
  - Don't upgrade openssl.
  - **Never exec on the host** without the user's approval.
  - The `read` tool sometimes lags new files by ~20 s.

## Session log

### 2026-11-24 — session 3 (v3 + foyer-os)
- Diagnosed "no apps launched" (PATH, then root sandbox) and "no network info"
  (PATH, plus job results dropped by unregistered SDL events). Both are fixed
  and verified on the box with a uinput virtual keyboard.
- Renamed big-launcher to **Foyer** and created **foyer-os**. Branches were
  consolidated to `main`, with archive tags.
- Wrote the UI engine (flex layout, dp units, springs, spatial focus, scroller,
  9-slice canvas, async asset cache, text cache) and the v3 screens, about 6k
  LOC with 32 test cases. The screenshot matrix (480p, 720p, 1080p, 21:9, 4K)
  was reviewed.
- Added the TOML model, the legacy importer, and three themes.
- Built the rootless build framework (bwrap Alpine, APKBUILDs, profiles,
  provision, make-image, QEMU boot test) and set up CI.
- Found and fixed on the box:
  - Audio defaulted to analog, so HDMI restore was added.
  - wpctl volume was reported as 0, now converted ×100.
  - evdev now hotplugs.
  - Foyer hung on a stale PipeWire.
  - session.sh was shadowed by an `.apk-new` copy, so it moved to `/usr/lib`.

(Earlier sessions: v1/v2 history is in `plans/big-launcher-frontend.md` and git
history before `bfccda5`.)
