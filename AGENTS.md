# foyer-os — Project & Handoff

Living document for this repo (**JuggyMcNutty/foyer-os**) and the launcher
submodule (**JuggyMcNutty/foyer**). **Keep "Current state" and "Session log"
updated every session**; future sessions start here.

## Overview

A reproducible living-room appliance:

- **Base:** Alpine 3.24 (musl, OpenRC) on the current box, or Debian trixie
  (glibc, systemd), chosen by the `BASE=` field of the profile. Debian is
  intended for the 4K board: glibc apps and Widevine-capable browsers.
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
box: Geobook 240 board, N5030, 8 GB RAM, 128 GB SATA disk in a USB dock,
HDMI 1.4 to a 4K TV; the old ideapad 120S is in
[hardwarefacts-ideapad-120s.md](hardwarefacts-ideapad-120s.md)).

## Access

| How | Detail |
|---|---|
| SSH | `ssh htpc` → `root@192.168.1.123`, key auth only (image ships key-only; DNS: `streamyboi`) |
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
| .debs (trixie) | `scripts/build-debs.sh` → `out/debs/trixie/` |
| Portable glibc Foyer | `scripts/build-portable.sh` → `out/foyer-<ver>-x86_64-glibc.tar.zst` (bookworm-built, glibc ≤ 2.36) |
| Debian image | `scripts/make-image-debian.sh qemu-debian\|generic-x86_64-debian --ssh-key …` |
| Release | push a `v*` tag → CI builds APKs, .debs, the tarball and images (alpine + debian), boot-tests both, attaches everything + SHA256SUMS |

## Current state

- [x] **New box online: Geobook 240 (N5030, 8 GB)** replaces the ideapad.
  First-ever fresh-image install (make-image.sh → dd to a USB-docked disk →
  UEFI boot) worked end-to-end on real hardware. Fixed during bring-up:
  image never created the swapfile, never wrote `/etc/foyer/env.d/libva.conf`
  (profile `VA_DRIVER` ignored), chrony dir left root:root, SOF driver stole
  the HDA controller (no soundcards — now forced to legacy HDA via
  `dsp_driver=1`), USB NIC late-enumeration (60 s retry in foyer-net.start).
  4K HEVC 10-bit decodes at ~1.3× realtime with i965 (iHD is broken here too:
  ~38× slower than realtime). HDMI is still 1.4 on this SoC: 4K60 only in
  4:2:0, no 4:4:4 above 30 Hz, no HDR. Details in hardwarefacts.md and the
  session 8 log.
- [x] **Apps launch.** Two root causes are fixed: the init PATH lacked
  `/usr/local/bin`, and Chromium/QtWebEngine refuse to run as root without
  `--no-sandbox`. Failures now show a toast with the reason, and each app has
  its own log.
- [x] **Network page** shows per-interface IP, speed, gateway, DNS and MAC.
- [x] **Foyer v3**: Big-Picture shell, settings (all pages), layout and app
  editors, OSK, quick panel (gamescope overlay), TOML config, themes
  (Midnight / Daylight / OLED plus drop-in), keep/revert for resolution
  changes. Verified on the box.
- [x] **Resolution**: **native-first** — the session defaults to the monitor's
  own (native) resolution: `WIDTH=native` in session.conf, resolved at boot by
  `session.sh` via `foyer-ctl display native` (gamescope still gets concrete
  `-W/-H/-r`); "Automatic" (monitor preferred) stays selectable. Real EDID
  modes listed as res@Hz, render-size cap per profile, 15 s keep/revert with
  automatic revert in `session.sh`.
- [x] **Panel info + stats**: `foyer-ctl display modes` parses the EDID (base +
  CTA-861, POSIX awk, tables harvested from edid-decode) — modes with real
  refresh rates plus HDR/VRR/colour/deep colour/link clocks; Settings → Display
  shows them. Settings → Stats polls `foyer-ctl sys stats` (CPU + per-core,
  GPU, memory, storage, temperatures, network rates) every 2 s.
- [x] **Build framework**: bwrap Alpine sandbox, 6 APKBUILDs, profiles,
  provision.sh, rootless make-image.sh, QEMU boot test (BIOS + UEFI pass).
  The box was re-provisioned from APKs; `/usr/local` is empty.
- [x] CI: foyer (Alpine and bookworm), foyer-os (APKs → images → boot test →
  release).
- [x] **Jellyfin HEVC plays**: root cause was the VAAPI driver pick on the
  Gen9 box (`iHD` advertises HEVC but decodes ~15× too slow → mpv `auto-copy`
  slideshow). Fixed via `foyer-app` env.d (`LIBVA_DRIVER_NAME=i965`, profile
  `VA_DRIVER`) — 8-bit HEVC now hw-decodes (~200 fps), 10-bit falls back to
  software (~4× realtime).
- **Follow-up (same day): first apply didn't take.** Two findings: (1) the box
  rebooted ~15:00 (user restart) — patches on disk survived, nothing to do;
  (2) the real bug: the env.d file set `LIBVA_DRIVER_NAME=i965` as a plain
  shell var — `foyer-app` sources env.d in its own shell, and without
  `export` the value never reached `exec jellyfin-desktop` (proved with
  `sh -c '. env.d/libva.conf; env | grep ^LIBVA'` → empty before, present
  after adding `export`). Fixed the box file + `provision.sh` now writes
  `export LIBVA_DRIVER_NAME=...`. Note for env.d drop-ins: **they must
  `export` their vars** (sourced, not exec'd).
- [ ] **TV check by the user**: navigation feel, the overlay over Jellyfin/Red,
  sound.
- [ ] Prime Video DRM (no Widevine on Alpine; the Debian base may fix it).
- [ ] IPTV playlist is still a placeholder.
- [x] Phase E (Debian/glibc):
  - rootless Debian sandbox (`debian-env.sh`) and `.deb`s for foyer,
    foyer-session, foyer-update and foyer-jellyfin-desktop;
  - systemd unit `foyer-session.service` plus OpenRC/systemd `foyer-ctl`
    backends and NetworkManager WiFi;
  - `make-image-debian.sh`. The QEMU boot passes under BIOS and UEFI;
  - `provision.sh` works against stock trixie (tested on a VM).
- [ ] Red on Debian: needs Qt ≥ 6.11, but trixie has 6.8. YouTube on Debian
  uses the Chromium `youtube.com/tv` fallback in `foyer-app`.
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
  - **VAAPI must use the `i965` driver on this GPU** (Gen9/Apollo Lake): the
    newer `iHD` media-driver advertises HEVC decode but runs ~15× slower
    than real time on it — mpv's default `hwdec=auto-copy` then produces a
    slow-motion slideshow with audio at normal speed (measured: 20 s of
    1080p30 HEVC in 52 s with iHD vs 3 s with i965; software manages ~4×
    realtime). Set via `/etc/foyer/env.d/libva.conf` (`export LIBVA_DRIVER_NAME=i965`,
    written by provision from the profile's `VA_DRIVER`); `foyer-app` sources
    `env.d/*` — **env.d files must `export` their vars** (they are sourced,
    not exec'd; a missing export cost a whole debugging round once).
    `/etc/libva.conf` is ignored by this libva build. jellyfin-desktop
    (libmpv) and the IPTV mpv both ride on this.
  - **The Home key belongs to the launcher; app keymaps must not bind it.**
    Foyer's `evdev_global` is a **non-grabbing** reader: while an app has
    focus, every keypress reaches BOTH the app (focused window via
    gamescope/XWayland) and Foyer (raw `/dev/input`). Foyer maps
    Home/Menu/Vol/Mute to launcher globals (Home/Menu = quick panel).
    jellyfin-desktop binds keyboard `Home` → `step_backward`, which its TV
    input plugin maps to **previouschapter** — so opening the overlay
    jumped the movie to the start. The packaged build drops that binding
    (`aports/foyer-jellyfin-desktop` prepare sed); a drop-in
    `inputmaps/keyboard.json` in the profile data dir overrides the qrc map
    at runtime (same `name` + `idmatcher` replaces it). Same conflict class
    to watch for in any app's keymap (gamepad long-press GUIDE → "home" in
    Jellyfin's ds4 maps is still app-internal).
  - `session.sh` lives in `/usr/lib/foyer/` (package code). Config lives in
    `/etc/foyer/`, and `/etc/htpc` is a compat symlink.
- **Build sandbox**
  - It is a single-uid user namespace. apk can't chown or set setuid bits;
    the `/sbin/apk` wrapper in the sandbox clears the resulting stale error
    flags, and `make-image.sh` restores owners with `debugfs`.
  - Images need `CAP_SYS_CHROOT` inside the namespace (for apk scripts),
    which `alpine-env.sh` grants.
  - Debian: debootstrap runs in two stages, with a tar `--no-same-owner`
    shim plus the `nochown.so` preload (unmappable chown → success).
    Debian's gamescope is in trixie-backports and installs to `/usr/games`;
    the cloud kernel lacks virtio-gpu DRM.
- **Dev machine** (Arch distrobox)
  - Don't upgrade openssl.
  - **Never exec on the host** without the user's approval.
  - The `read` tool sometimes lags new files by ~20 s.

## Session log

### 2026-11-26 — session 8 (Geobook 240 N5030 online as the new box)

- **New device:** GEOMARK Geobook 240 board (N5030 Gemini Lake, UHD 605, 8 GB,
  128 GB SATA in a PNY USB3.0 dock) replacing the ideapad. First-ever fresh
  image install: `make-image.sh geobook-240` → `zstd|dd` to the docked disk →
  UEFI boot. Worked end-to-end (UEFI USB boot, first-boot grow to 111.5 GB,
  key-only SSH, 4K60 output to a dummy plug, HDMI audio).
- **Deploy issues found and fixed in `make-image.sh`** (all verified on the box
  after the fix):
  - swapfile: fstab entry existed but the file was never created (only
    provision.sh created it) → firstboot now creates it from
    `/etc/foyer/swap_mb` (size from the profile's `SWAP_MB`), image stays small.
  - VAAPI: profile `VA_DRIVER` was never applied on image installs (only
    provision wrote env.d) → image now writes `/etc/foyer/env.d/libva.conf`.
  - audio: the kernel SOF driver (`sof-audio-pci-intel-apl`) claimed the HDA
    controller and, lacking `sof-firmware`, created **no soundcards**. Image now
    ships `/etc/modprobe.d/foyer-audio.conf` with
    `options snd-intel-dspcfg dsp_driver=1` (legacy HDA; `0`=auto picks SOF —
    the first attempt used 0 and silently kept SOF).
  - chrony: `/var/lib/chrony` landed root:root (sandbox apk can't chown) →
    drift file "Permission denied". `fix_owners` now chowns it to chrony.
  - network: USB r8153 can enumerate after networking starts → no IP until
    reboot. `foyer-net.start` now re-checks for 60 s in the background.
- **VAAPI benchmark (4K HEVC Main10, 5 s, `mpv --vo=null --untimed
  --hwdec=vaapi-copy`):** i965 3.8 s (~1.3× realtime), iHD **190 s** (~38×
  slower than realtime — iHD is broken on Gemini Lake too, like Apollo Lake),
  software 3.3 s (~1.5×). Profile `VA_DRIVER=i965` is mandatory, not optional.
- **HDMI reality:** N5030 (Gemini Lake) is HDMI 1.4 — the 4K60 full-color +
  HDR goal is **not** met by this board (4K60 needs 4:2:0, 4:4:4 tops at 30 Hz,
  no HDR metadata). The decode side is fixed; the link is not. The dummy plug
  (emulates AOC 28E850 HDR, 3840x2160@60 native) confirmed the display path;
  a real TV check is still pending.
- **Box quirks** (in hardwarefacts.md): r8153 USB Ethernet sometimes doesn't
  come up at boot (reboot fixes); a broken Realtek c821 BT dongle is stuck in
  a USB reset loop (unplug it); RTC is unset until chrony steps the clock.
- **Note:** the previous sessions' work (4–7: EDID parser, native resolution,
  stats page, VAAPI/Home-key fixes) was still uncommitted; committed separately
  before this session's changes.

### 2026-11-25 — session 7 (Home key restarted Jellyfin movies)

- **Symptom:** pressing Home while watching a movie in Jellyfin (to open the
  overlay menu) made Jellyfin start the movie from the beginning.
- **Root cause:** Foyer's `evdev_global` is a **non-grabbing** raw reader: the
  same keypress reaches the focused app (gamescope/XWayland) AND Foyer.
  Foyer maps Home → quick panel (overlay) — by design — but
  jellyfin-desktop's keyboard map (`resources/inputmaps/keyboard.json`)
  binds `"Home": "step_backward"`, and the TV input plugin
  (`native/inputPlugin.js`) maps `step_backward` → **previouschapter**. One
  press = overlay opens + movie jumps to its start. (Noticed: Jellyfin had
  also died once — quick panel "Back to Foyer" SIGTERMs it; exit 143 is
  treated as user-closed, silent.)
- **Fix:** drop the Home binding from the packaged Jellyfin
  (`aports/foyer-jellyfin-desktop/APKBUILD` prepare sed, pkgrel 0 → 1) and
  drop a runtime override on the box now:
  `/var/lib/foyer/share/jellyfin-desktop/profiles/<hash>/inputmaps/keyboard.json`
  (full default map minus Home; InputMapping loads the profile dir after
  qrc and replaces by map `name`, with a QFileSystemWatcher). Validated the
  JSON locally (comments stripped, 66 mappings, no Home).
- Also confirmed harmless: Jellyfin's volume/Mute keys are unbound, so the
  launcher's Vol/Mute globals don't double-apply; the second Home press
  while the overlay is open goes only to the overlay (gamescope focus +
  foyer's `overlay_proc_.alive()` guard).

### 2026-11-25 — session 6 (why selecting 4K fell back to 1080p)

- **Symptom:** picking either 4K resolution in Settings → Display on the box
  "falls back" to 1080p.
- **Root cause (all verified on the box):** session.conf had been left at
  `WIDTH=3840 HEIGHT=2160 RATE=60` (confirmed pick). The Toshiba TV EDID has
  **no 2160p60 timing at all** — 2160p only exists at 24/25/30 Hz (297 MHz
  pixel clock; HDMI 1.4 tops out at 340 MHz, 50/60 Hz would need 594+ MHz).
  gamescope is told `-r 60`, finds no such mode, keeps the current mode →
  1080p60 (live pipe confirmed 1920x1080@60). The picker they used is the
  **old build** still installed on the box (foyer 3.0.0-r2): it lists sysfs
  mode names, which carry no refresh rates, and invents 60/50/30 Hz variants
  for every mode — so "3840x2160 60 Hz"/"4096x2160 60 Hz" were fiction.
- **Parser bug found while checking the TV EDID:** the new EDID parser missed
  the **HDMI VIC list** in the HDMI VSDB (CTA-861-F: gated by x[4]&0x20,
  3D byte x[5], count byte x[6] top 3 bits, VICs follow, latency fields
  shift) — where this TV keeps 3840x2160@30/25 and 4096x2160@24, which do
  NOT appear in the CTA video data block. Native would have resolved to
  @24 instead of @30. Fixed in `session/bin/foyer-ctl` (embedded copy
  re-synced) and `/tmp/edidwork/edid.awk`; re-verified against both real
  EDIDs (Toshiba: native 3840x2160@30; AOC: native 3840x2160@60 unchanged)
  under gawk and busybox awk (Alpine sandbox); empty/garbage EDIDs still
  exit 1 cleanly.
- **Deployed:** bumped pkgrels (foyer r3, foyer-session r4), rebuilt the two
  APKs, provisioned the box (`scripts/provision.sh ideapad-120s htpc`),
  then `foyer-ctl display mode/set native`. Verified live: scanout
  3840x2160@30, gamescope `-W 3840 -H 2160 -r 30 -w 1920 -h 1080`,
  `display native` = 3840x2160@30, session.conf `WIDTH=native` (resolved
  at boot by session.sh). NOTE: provision's "keep a picked WIDTH" logic
  preserved the broken `WIDTH=3840/2160/RATE=60` on the first pass — the
  end state needed an explicit `mode/set native` afterwards.
- Also note: with 4K@30 output the launcher UI still renders at 1080p by
  design (profile `RENDER_MAX=1920x1080`, gamescope upscales), so "Launcher
  surface 1920x1080" in Settings → Current is expected — the TV OSD shows
  the true output mode.
- **Pending user checks:** keep-revert dialog confirm on the TV (or the
  session auto-reverts to 1080p after ~25 s), Jellyfin HEVC playback with
  the exported env.

### 2026-11-25 — session 5 (Jellyfin HEVC playback fix)

- **Symptom:** HEVC SDR 1080p played at a very low frame rate / slow motion,
  audio at normal speed (desync growing). H.264 content was fine.
- **Diagnosis on the box:** HEVC VAAPI profiles are exposed (vainfo) and the
  hardware is fine — but *which* libva driver gets picked is the bug.
  `jellyfin-desktop` (Qt + libmpv) defaults to `hwdec=auto-copy`; mpv's auto
  chain tries ffmpeg's new **Vulkan** hwaccel first (fails: Gen9 i915 has no
  `VK_KHR_video_decode_queue`), then falls to `vaapi-copy` — and with the
  default **`iHD` (intel-media-driver 26.2.1)** that path decodes ~15× slower
  than real time. Measured with `mpv --vo=null --untimed --frames=600` on a
  10 s 1080p30 libx265 test clip (20 s of content):
  - `--hwdec=no` (software): 5 s — ~4× realtime
  - `--hwdec=auto` / `vaapi-copy` with `iHD`: **52 s — ~11 fps** (the bug)
  - same with `LIBVA_DRIVER_NAME=i965`: **3 s — ~200 fps** (the fix)
  - 10-bit Main10 + explicit `vaapi-copy` + i965: 4 s (the `auto` chain
    breaks on Main10 via the Vulkan attempt + NAL parse error, but the
    software fallback still plays it at ~4× realtime)
- **Fix (box + repo):** `foyer-app` now sources `/etc/foyer/env.d/*`, and
  provision writes `LIBVA_DRIVER_NAME=i965` there from the profile's new
  `VA_DRIVER` flag (`profiles/ideapad-120s.sh`). Applied live on the box
  (patched `/usr/bin/foyer-app`, wrote the env.d file, killed the running
  app; verified the wrapper matches the repo). `/etc/libva.conf` is ignored
  by this libva build — env var it is. NOTE: the wrapper sources env.d at
  **every app launch**, so a plain app relaunch picks it up — no session
  restart needed.
- Also installed `libva-utils` (vainfo) on the box for diagnostics; test
  clips `/tmp/hevc1080.mp4`, `/tmp/hevc1080-10bit.mp4` (delete when done).

### 2026-11-25 — session 4 (native-res default, EDID panel info, stats page)

- **Native resolution by default.** This monitor and the TV are 4K native, so the
  session now always targets the panel's native mode: the highest-area EDID mode of
  the preferred aspect. `session.conf` ships `WIDTH=native`; `session.sh` resolves it
  to concrete gamescope `-W/-H/-r` numbers at boot via `foyer-ctl display native`
  (no EDID → falls back to the monitor preferred mode). `display mode/get|set`
  accept `native`; provision keeps `WIDTH=native` values; the .deb template writes it.
- **EDID parsing in foyer-ctl** (`display modes`, `display native`): base block +
  CTA-861 in POSIX awk, with embedded mode tables harvested from edid-decode
  (established timings I/II and VIC 1-127/193-218). Reports every mode with its real
  refresh rate (interlaced dropped), native/preferred flags, and panel info:
  name/make/model/year/size, HDR EOTF + desired peak luminance, VRR (HDMI 2.1
  HF-VSDB + AMD FreeSync), ALLM, colorimetry, deep colour, the 4:2:0 capability
  map, max TMDS/character rate, SCDC and LPCM/formats. Validated field-by-field
  against edid-decode on a real 4K EDID (AOC Q32G3WG3R3: native 3840x2160@60,
  preferred 2560x1440@60, HDR10, FreeSync 48-144) and re-run under busybox awk
  inside the Alpine sandbox. Bad checksums/short EDIDs fall back to sysfs names@60.
- **Settings → Display**: res@Hz mode picker (Native / Automatic / every EDID
  mode) plus a Panel section (Display, Size, Native, Preferred, HDR, VRR, gamut,
  deep colour, audio, link clock). Parsing moved into `sysctl.cpp` with doctest
  suites (DisplayReport/SysStats; 36 cases, 282 assertions pass).
- **Settings → Stats page** (new category): live CPU total + per core, load,
  processes, uptime, RAM/swap, storage, GPU busy% + clock (amdgpu sysfs, i915 gt
  sysfs, pp_dpm_sclk), per-zone temperatures, per-interface network rates.
  Refreshes every 2 s via `foyer-ctl sys stats`, which samples /proc twice 0.5 s
  apart so each call is self-contained (screenshot mode shows real numbers).
  `foyer` also gained the `:stats` open command.

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

- Phase E: Debian trixie base done end to end (sandbox, .debs, systemd
  session, image, QEMU boot, provisioning a stock trixie VM). There is now a
  portable glibc tarball, and the CI matrix covers alpine/debian × profiles.

(Earlier sessions: v1/v2 history is in `plans/big-launcher-frontend.md` and git
history before `bfccda5`.)
