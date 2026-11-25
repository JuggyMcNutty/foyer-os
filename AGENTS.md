# HTPC — Project & Handoff

Living document for the HTPC mini-PC build. **Keep "Current state" and "Session log" updated every session** — future sessions start here.

## Overview

Turn the box at `192.168.1.123` into a living-room media/streaming machine:

- **Compositor:** Gamescope (Wayland, Valve's Steam-Deck compositor)
- **Audio:** PipeWire (+ pipewire-pulse for app compat)
- **Front door:** a big-picture launcher (grid UI, remote-friendly) for picking apps — **Kodi is ruled out** (user doesn't like it)
- **Apps:** Jellyfin, YouTube, other streaming

The hardware is a repurposed laptop motherboard in a mini-PC enclosure (donor: Lenovo ideapad 120S-11IAP, Celeron N3350). Full details in **[hardwarefacts.md](hardwarefacts.md)** — read it before designing around the machine.

Key constraints shaping everything: **2 GB RAM, no AVX, 32 GB eMMC, 1080p60 HDMI 1.4.** Wiring is simple: HDMI direct to the board, r8152 USB-C Ethernet **direct** to the board's USB port (the temporary Nintendo hub has been removed).

## Access

| How | Detail |
|---|---|
| SSH (preferred) | `ssh htpc` → `root@192.168.1.123` — **key auth configured** (alias in dev machine's `~/.ssh/config`) |
| Fallback | root password auth still enabled (password kept out of git; see your password manager) |
| Project dir (dev side) | this directory (`.../Documents/projects/htpc`) |

## Target stack (planned)

| Layer | Choice | Notes |
|---|---|---|
| OS | Alpine 3.24.4 (OpenRC, musl) | already installed |
| Compositor | `gamescope` (community repo) | autostart on boot, fullscreen on HDMI, 1080p60 |
| Audio | `pipewire` + `pipewire-pulse` (community, OpenRC services exist) | HDMI out to TV as default sink |
| Launcher | **big-launcher** (complexlogic/big-launcher, forked) — C++/SDL3 Roku-style grid UI | cloned to `./big-launcher` + our fixes; builds cleanly on dev machine |
| Jellyfin | **jellyfin-desktop** (official Qt6+libmpv client, built natively on box) | chosen over Fladder (Flutter; would need Flatpak/glibc layer on musl) & over chromium kiosk; URL https://sexbox.lan/jellyfin |
| YouTube | **Red** (`--tv`, TV mode = living-room UI) + `youtube.com/tv` in chromium as backup | Red = github.com/keshavbhatt/red, Qt6/C++20, built from source |
| Prime Video | chromium `--kiosk` to primevideo | ⚠️ Alpine chromium has no Widevine → DRM playback may fail; test on TV |
| Twitch | chromium `--kiosk` to twitch.tv | DRM-free, should work |
| IPTV | mpv `--fs` + m3u playlist (`/etc/htpc/iptv.m3u`) | playlist is a placeholder |

Alpine repo notes: `gamescope`, `pipewire-openrc`, `pipewire-pulse-openrc`, `mpv`, `yt-dlp`, `chromium`, `mesa-vulkan-intel`, `wireplumber`, `sdl3`, `sdl3_ttf`, `qt6-qtbase/-webengine/-qtsvg/-qtwebchannel` (all 6.11.1 ≥ Red's 6.11 floor) all exist in v3.24 community. **NOT packaged:** `sdl3_image` (build SDL_image from source), `steam` client. Note: `qt6-qtdeclarative` also needed as dep.

## Current state

### v2 rewrite (on `v2` branch — **now shipping on the box**)

The **v2 full rewrite** is on the `v2` branch (fork: github.com/JuggyMcNutty/big-launcher) and is
**what the box runs today**. The `htpc` branch (v1) is kept as a working rollback. Scope in the
approved plan: quick-menu overlay, OSK, status bar, layout editor, full settings, CEC.

- [x] **v2 branch** created from `htpc`; CMake skeleton with `src/{core,platform,input,ui,screens,jobs,render}`, options `BL_CEC`/`BL_EVDEV`/`BL_WERROR`
- [x] **Core rewrite** (Phase 0 + Phase 1 parity + Phase 2 core):
  - `core/`: `App` (main loop, dirty-flag rendering), `Config` (INI read **and** write, preserves comments/order, atomic + `.bak`), `LayoutModel` (libxml2 read+write)
  - `platform/`: `Process` (fork+setsid+pidfd reap, kill-by-group, app state = PID alive), `power` (OpenRC), `sysctl` (htpc-ctl builder)
  - `input/`: `Action` enum + `ActionMapper` (keyboard/gamepad), `evdev_global` (`BL_EVDEV`), `cec` stub (`BL_CEC`)
  - `ui/`: `Screen`/`ScreenStack`, `ListScreen`, `Anim` (tweens), `TextSprite`, `shapes`
  - `screens/`: `home` (sidebar+grid), settings hub + audio/display/network/bluetooth/system/power/launcher pages
  - `jobs/`: `JobQueue` (worker thread + SDL user-event delivery)
  - `render/`: RAII `Texture`/`RendererSDL`, `theme`, moved image/text/sound/util
- [x] **Unit tests** (doctest): config round-trip, layout round-trip, action mapping, process reaping — **7/7 pass**
- [x] **Clean build** on dev machine (Arch) and box (Alpine/musl), `-Wall -Wextra` no warnings
- [x] **`htpc-ctl`** backend (`htpc-config/bin/htpc-ctl`): audio (wpctl), display (session.conf), wifi, bt, net, sys, power. Supersedes `htpc-net` (kept as compat symlink)
- [x] `install-on-box.sh` updated: installs `htpc-ctl`+`wpctl`+`libevdev`, generates `/etc/htpc/session.conf`, `session.sh` reads it
- [x] **Session-env crash FIXED** (commit `bb40b64`): the getopt short optstring was `"+c:ldh"` — missing `:` after `l`, so `-l` was a flag and `optarg` was null when `layout_path = optarg` ran → null `strlen` segfault. Now `"+c:l:dh"` + null-guarded optarg. (Also guarded `HOME`/`executable_dir` in `find_file`, commit `68c3e60`.)
- [x] **v2 launcher running in the init session** (verified: stable, ~280 MB RAM, no crash loop). Box now runs **v2**.
- [ ] User visual confirm on TV (grid, clock, settings, power tiles, status bar) — **in progress** (user at TV, overlay test started)
- [x] Parity check on box (layout.xml identical to dev, all `htpc-*` wrappers in place, RAM launcher ~275 MB + gamescope ~127 MB, loadavg ~0.06 idle)
- [x] Phase 2: settings pages wired to htpc-ctl — **verified on box**: audio (volume/mute/sinks via wpctl, session env), net status, sys info, wifi/bt graceful no-adapter; all screen `ctl()` calls have matching htpc-ctl commands
- [x] Log flush fix: spdlog default flush level is off → box log stayed 0 bytes; now `flush_on(info)` + info-level startup lines (`b01ff27`)
- [x] Global evdev input wired up: `EvdevGlobal` was never started (dead code) and used wrong keycodes (217/172 instead of KEY_HOME 102 / KEY_TV 377); now started in App, actions delivered on main thread via `EVT_GLOBAL_ACTION` SDL user event, only honored while an app is focused (`2e63932`). Box was missing `libevdev-dev` (headers) → `BL_EVDEV` had silently fallen off; installed + added to install-on-box.sh
- [x] Phase 3 (partial):
  - [x] Status bar (top: network + audio, refreshed via jobs every 5s)
  - [x] Toasts (already in App)
  - [x] OSK (`ui/text_input` QWERTY modal; WiFi password entry wired in)
  - [x] Layout editor (menu → entries → actions; edit title/command, reorder, add, delete; saves layout.xml; `:layout` + Settings tile)
  - [x] Quick-menu overlay (`GAMESCOPE_EXTERNAL_OVERLAY`): `big-launcher --overlay` spawned with the env var + `HTPC_APP_PID`; gamescope composites it on top of the running app. Home/Menu opens it. Back-to-home kills the app. (Needs TV visual confirm.)
  - [ ] CEC — **blocked**: no `/dev/cec`/`/sys/class/cec` on the box (HD 500 doesn't expose CEC; the `libcec` apk is for a Pulse-Eight USB adapter the box lacks). `BL_CEC` stub is in place; revisit if a USB CEC adapter is added.
- [x] Phase 4: cutover — **`v2` is the default branch of the fork** (JuggyMcNutty/big-launcher); FORK.md/README document v2 (commits `e92bb53` + default-branch note)

**Ops note:** gamescope ignores SIGTERM; restart the session with `kill -9 <gamescope-wl pid>` (inittab respawns session.sh).

### v1 (htpc branch — rollback fallback, no longer on the box)

- [x] Fresh Alpine 3.24.4 install (done by user, pre-session)
- [x] SSH key auth + `htpc` alias from dev machine
- [x] `hardwarefacts.md` written & verified (HDMI direct on board, no dock in end state)
- [x] **community repo enabled** on the box (was disabled → first apk installs silently failed; watch for this)
- [x] big-launcher forked to `./big-launcher`, builds clean on dev machine (fmt ≥10 include fixes + constexpr fix)
- [x] Red cloned to `./red` (dev build blocked by container openssl soname mess — **build on box instead**)
- [x] App lineup decided: Jellyfin, Red, YouTube, Prime Video, Twitch, IPTV
- [x] Launcher config written: `htpc-config/` (layout.xml, config.ini, icons/, bin/htpc-app wrappers, *.url files)
- [x] Install scripts written: `htpc-setup/push-to-box.sh` (dev side) + `install-on-box.sh` (box side)
- [x] **WORKING END-TO-END (2026-11-24):** box boots unattended into tty1 → session.sh → PipeWire + gamescope (1080p60) → big-launcher on the Toshiba TV. All procs verified after clean reboot.
- [x] Fork: github.com/JuggyMcNutty/big-launcher (`master`=pristine upstream, `htpc`=ours: fmt fixes, Clock, FORK.md, WiFi/BT settings screen)
- [x] Native Jellyfin client: jellyfin-desktop built on box, wired as Jellyfin tile with `--tv` (fallback: chromium kiosk)
- [x] WiFi/Bluetooth native settings UI in launcher (`:wifi`/`:bt`) — driven by `htpc-net` script; no radio yet, degrades gracefully
- [x] Clock, Settings menu tiles (wifi/bluetooth), power tiles (Reboot/Shutdown/Sleep/Restart UI) in layout
- [ ] User confirm visually: launcher grid + clock on TV, Settings tiles, power tiles, navigate with 2.4G keyboard
- [ ] Test app tiles: Jellyfin native (`--tv`, server https://sexbox.lan/jellyfin), Red (`--tv`), Twitch, IPTV, Prime Video (DRM likely fails — decide keep/drop)
- [ ] Test WiFi/BT pages once a USB dongle exists
- [x] Nintendo USB hub removed; r8152 plugged direct (verified 2026-11-24, session 2)
- [ ] (Later) swap password auth off (root password auth still active)

### Session-stack fixes (do not regress)
- Box needs **seatd** (openrc, default runlevel) + **eudev/udev-trigger** (sysinit) + **xwayland** + **hwdata** — see hardwarefacts.md "Session-stack gotchas"
- Red built with `-DCMAKE_SKIP_INSTALL_RPATH=ON -DRED_BUILD_TESTS=OFF`; big-launcher fork has fmt≥10 + constexpr fixes
- `install-on-box.sh` now installs/wires all of the above; re-running it is safe

## Dev machine gotchas

- **Arch distrobox container**: repo openssl is 4.x but installed is 3.6.5 → `qt6` tools (rcc) fail with `libcrypto.so.4` missing. **Don't upgrade openssl** (breaks sudo/pacman). Red builds on the **box** instead.
- pacman needed `-Sy` refresh before installing (stale db → 404s).
- `sdl3_image` was the only missing Arch package; `sudo pacman -S spdlog sdl3_image` fixed big-launcher dev builds.

## Conventions & gotchas

- **OpenRC, not systemd** — services via `/etc/init.d/*` + `rc-update add <svc> default`
- **Networking = ifupdown-ng** (`/etc/network/interfaces`), DHCP currently
- **musl** — prefer packaged software; glibc-only apps need AppImage/glibc compat work
- `/tmp` and `/run` are tmpfs; **eMMC swap exists but is slow** — keep the resident set under ~1.5 GB
- No AVX — don't assume it in build choices
- **Network = r8152 direct** to the board's USB port (the temporary Nintendo hub has been removed). If the r8152/USB port fails, the box is unreachable — keep SSH keys working.
- No Wi-Fi, no battery, no internal screen — it's a headless box on the TV
- **HDMI is direct to the motherboard** (no dock/adapter); network = r8152 USB-C adapter **direct** to the board's USB port
- Display is **1080p60** — test everything at 1080p

## Open questions

1. **~~Jellyfin server address~~** — RESOLVED 2026-11-24: **`https://sexbox.lan/jellyfin`** (staged in `htpc-config/jellyfin.url`)
2. **IPTV playlist source** — placeholder m3u; needs real channels
3. **Prime Video DRM** — no Widevine in Alpine chromium; if it doesn't play, options are a CDM-enabled browser build or dropping the tile.

Answered this session: launcher = big-launcher fork (✓), apps = Jellyfin/Red/YouTube/Prime/Twitch/IPTV (✓), gaming = none (✓), storage = eMMC only for now (✓).

## Session log

### 2026-11-24 — session 1 (discovery + docs)
- Connected over SSH (password), installed key auth, added `htpc` alias to dev `~/.ssh/config`
- Discovered donor hardware: Lenovo ideapad 120S-11IAP board in mini-PC case (Celeron N3350, 2 GB, 32 GB eMMC, HD 500)
- Confirmed: HDMI 1080p, USB r8152 Ethernet (DHCP 192.168.1.123), no battery, no Wi-Fi, empty SATA + microSD
- Audited Alpine v3.24 packages for the whole target stack (gamescope/pipewire/mpv/yt-dlp etc. all available; steam/red are not)
- Wrote `hardwarefacts.md` and this file
- User clarifications: repurposed laptop board (no battery by design); **no Kodi**; **HDMI is direct to the motherboard** (no dock/adapter); the Nintendo USB hub is temporary and will be removed — the r8152 USB-C adapter plugs **directly** into the board's USB port in the end state
- **Next session:** resolve open questions (launcher, app lineup, gaming, storage), then install Gamescope + PipeWire and get to a fullscreen session

### 2026-11-24 — session 1 continued (fork + network UI)
- **Proper fork created**: github.com/JuggyMcNutty/big-launcher — `master` pristine upstream (53 commits), `htpc` = our branch (fmt fixes, Clock, FORK.md, WiFi/BT screen). Direct commits to `htpc` per user choice.
- **Clock implemented** (upstream never finished it): new `BL::Clock`, `[Clock] Enabled/Format` config, renders at bottom of sidebar, re-renders only on displayed-string change.
- **WiFi/Bluetooth native settings screen**: `BL::SettingsScreen` (WiFi + BT pages), `BL::net` layer, `:wifi`/`:bt` special commands, key+text-input routing, blend mode fix in `set_color_mod`. Driven by **`htpc-config/bin/htpc-net`** (wpa_cli + bluetoothctl helper, installed to /usr/local/bin). No radio in box today — pages degrade gracefully until a USB dongle appears.
- Settings menu tiles added to layout.xml (+ hand-made wifi/bluetooth SVG icons); power tiles (Reboot/Shutdown/Sleep/Restart UI) in sidebar.
- install-on-box.sh now also installs `wpa_supplicant bluez bluez-openrc dbus dbus-openrc iw` + services; htpc-net copied to /usr/local/bin.
- **In flight:** full push + rebuild incl. jellyfin-desktop (python3-dev apk error fixed via `apk update` + `apk fix`; previous run died on stale repo index).
- **Next:** verify launcher (clock/settings/power) + jellyfin-desktop on TV; wire `htpc-jellyfin` wrapper to `/usr/local/bin/jellyfin-desktop`.
- First boot: gamescope never started → root-caused chain: (1) **libseat had no seat backend** → installed `seatd` + openrc service; (2) **libinput found no input devices** → box uses busybox mdev, not udev → installed `eudev` + `udev-trigger` (sysinit); (3) gamescope then **segfaulted** (`segfault at 90`) → root cause `Cannot find Xwayland binary` — gamescope 3.16 requires Xwayland even for wayland-native clients → installed `xwayland` (+ `hwdata` for pnp.ids)
- After fixes: **gamescope + Xwayland + big-launcher all running**; clean reboot test passed — full stack unattended via `tty1::respawn:/bin/sh /etc/htpc/session.sh` in `/etc/inittab`
- Display facts confirmed from EDID via gamescope log: **Toshiba 4K TV**, link caps at 1080p60 (HDMI 1.4) → documented in hardwarefacts.md
- Jellyfin URL set: **https://sexbox.lan/jellyfin** (pushed to box, verified in `/etc/htpc/jellyfin.url`)
- Red installed to `/usr/local/bin/red` (built on box; RPATH install issue worked around with `-DCMAKE_SKIP_INSTALL_RPATH=ON`)
- `install-on-box.sh` updated with the full session-stack package set + openrc wiring; re-runs are idempotent
- **Remaining:** user visual confirmation, per-app testing (Red TV mode, Jellyfin, Twitch, IPTV, Prime DRM), input sanity from couch
- Enabled **community repo** on the box (was commented out → all community packages "missing"; apk update quiet)
- Dev machine (Arch container): installed sdl3_image + spdlog (pacman), fixed fmt≥10 include fixes in big-launcher (`fmt/format.h`), constexpr fix; builds clean
- Dev container **openssl soname trap**: qt6 rcc wants libcrypto.so.4, installed is .so3, upgrading breaks sudo/pacman → **Red is built on the box instead**
- Box: full apk stack install done (gamescope, pipewire+pulse, wireplumber, qt6 6.11.1 full set incl. qtwebengine, mesa, vulkan, sdl3, build tools) — 467 pkgs, 13% disk
- Cloned Red (github.com/keshavbhatt/red) → confirmed Qt6.11 floor, `--tv` TV mode flag exists
- Decided app lineup + wrote configs: `htpc-config/` (layout.xml w/ asset-relative icon paths — IMG_Load resolves relative to CWD, config.ini w/ clock+screensaver+gamepad on, htpc-app wrappers w/ *.url indirection, custom icons for amazon/iptv, placeholder jellyfin URL + iptv.m3u)
- Wrote `htpc-setup/push-to-box.sh` + `install-on-box.sh` (builds SDL3_image from source — not packaged on Alpine, builds big-launcher + Red on box, installs launcher to /opt/htpc/launcher, session.sh w/ pipewire+gamescope, tty1 respawn via /etc/inittab)
- **In flight:** push + build on box (Red compile is the long pole)
- **Next:** reboot box → verify gamescope+launcher on TV → test each app tile → fix Jellyfin URL → Prime DRM check

### 2026-11-24 — session 2 (v2 rewrite)
- User approved the **v2 full rewrite** (couch frontend): quick-menu overlay, OSK, status bar + notifications, in-UI layout editor, full settings (audio/display/network/BT/system/power/launcher), CEC. New `src/` layout, RAII, action-based input, dirty-flag rendering, nothing blocks the UI thread.
- **v2 branch** created from `htpc`. Removed the old god-class files (layout.*, menu*, sidebar_*, settings_screen, network, gamepad, hotkey, screensaver, clock, platform/{unix,win32}).
- **Core rewrite done** (Phase 0 + 1 parity + 2 core): `core/{App,Config,LayoutModel}`, `platform/{Process,power,sysctl}`, `input/{Action,ActionMapper,evdev_global,cec}`, `ui/{Screen,ScreenStack,ListScreen,Anim,TextSprite,shapes}`, `screens/{home, settings/*}`, `jobs/JobQueue`, `render/{Texture,RendererSDL,theme}`. Config is now read **and** written (atomic + .bak, preserves comments/order) — unlocks the in-UI layout editor.
- **Unit tests** (doctest) added: config round-trip, layout round-trip, action mapping, process reaping — **7/7 pass**.
- **Clean build** on dev machine (Arch) and box (Alpine/musl), `-Wall -Wextra` no warnings. CMake options `BL_CEC`/`BL_EVDEV`/`BL_WERROR`.
- **`htpc-ctl`** backend written (`htpc-config/bin/htpc-ctl`): audio (wpctl), display (session.conf + gamescope restart), wifi, bt, net, sys, power. Supersedes `htpc-net` (kept as compat symlink). `install-on-box.sh` updated (installs htpc-ctl+wpctl+libevdev, generates `/etc/htpc/session.conf`).
- **Session-env crash FIXED** (`bb40b64`): getopt short optstring was `"+c:ldh"` — missing `:` after `l`, so `-l` was a flag and `optarg` was null → null `strlen` segfault at startup. Fixed to `"+c:l:dh"` + null-guarded optarg. (Also guarded `HOME`/`executable_dir` in `find_file`, `68c3e60`.)
- **v2 launcher now running in the init session** (stable, ~280 MB RAM, no crash loop). Box runs **v2**.
- **Phase 3 (partial) done:**
  - **OSK** (`ui/text_input`): QWERTY modal, D-pad nav, shift, mask, submit/cancel. Fixed use-after-free (capture callbacks before `screens().pop()`). WiFi connect now prompts for password.
  - **Status bar** (`ui/status_bar`): top bar with network + audio, refreshed via jobs every 5s, drawn by App when no app running.
  - **Layout editor** (`screens/settings/layout_editor`): three-level (menu → entries → actions). Edit title/command via OSK, reorder, add, delete. Saves layout.xml on change. `:layout` command + Settings tile.
  - Fixed `htpc-ctl` audio sinks (was `wpctl enumerate` → now `wpctl list audio sinks`) + sys uptime (busybox has no `-p`).
  - Fixed logging: create log dir before opening sink (HOME=/ in session → log at `/.local/share/big-launcher/`).
- **Ops:** gamescope ignores SIGTERM; restart session with `kill -9 <gamescope-wl pid>`.
- **Nintendo USB hub removed** (user): r8152 + 2.4 GHz receivers now plug direct to the board's USB port. Verified `eth0` up at 192.168.1.123, no hub in `lsusb`, `/dev/sda` (hub's mass-storage) gone. Updated AGENTS.md + hardwarefacts.md.
- **Quick-menu overlay done** (`GAMESCOPE_EXTERNAL_OVERLAY`): `big-launcher --overlay` (minimal app, dimmed transparent bg) spawned with the env var + `HTPC_APP_PID`; gamescope composites it on top of the running app. Home/Menu opens it; back-to-home kills the app. Fixed Sound teardown (destroy before `SDL_Quit`). Overlay verified: connects to `gamescope-0`, runs, exits cleanly.
- **Next:** CEC (libcec + remote test), user visual confirm on TV (grid, status bar, OSK, layout editor, quick menu), parity check, Phase 4 cutover.

### 2026-11-24 — session 2 continued (parity, box fixes, cutover, TV test)
- **Parity check on box done**: layout.xml identical to dev, all `htpc-*` wrappers present, launcher ~275 MB + gamescope ~127 MB RAM, loadavg ~0.06 (idle ~0%).
- **Phase 2 box test done**: exercised `htpc-ctl` (audio volume/mute/sinks via wpctl, net status, sys info, wifi/bt no-adapter paths) with the session env; every `ctl()` call from the settings screens has a matching htpc-ctl command. Note: wpctl/htpc-ctl audio needs the session env (`XDG_RUNTIME_DIR=/run/htpc-session`) — plain SSH shells can't see PipeWire.
- **Log flush bug fixed** (`b01ff27`): spdlog's default flush level is off → the box log stayed 0 bytes across restarts. `flush_on(info)` + startup lines at info. Verified: log now writes `App initialized` / `Begin main loop` / `evdev: monitoring N devices`.
- **Global evdev input was dead code — now works** (`2e63932`): `EvdevGlobal` was constructed but never `start()`ed and its callback never set, so Home/Volume did nothing while an app was focused. Keycodes were also wrong (217/172 vs real KEY_HOME=102/KEY_TV=377); now uses `<linux/input-event-codes.h>` + KEY_MENU. Actions delivered to the main thread via `EVT_GLOBAL_ACTION` SDL user event; honored only while an app is focused and no overlay is up. **Root cause of the box never having evdev:** `libevdev-dev` (headers) was missing → pkg-config failed → `BL_EVDEV` silently off. Installed it, added to install-on-box.sh.
- **Empty-text render fix**: status bar rendered empty network/audio sprites at startup → `Could not render text ''` (SDL_ttf returns NULL for ""). `render_text` now returns a 1x1 transparent surface for empty input.
- **Phase 4 cutover done**: `v2` pushed to the fork and set as the **default branch** of JuggyMcNutty/big-launcher; FORK.md/README document v2.
- **In flight:** user at TV testing the quick-menu overlay end-to-end (launch app → Home key → overlay → back to home).
- **Next:** user visual confirm (grid/status bar/OSK/layout editor), per-app tile tests (Jellyfin/Red/YouTube/Twitch/Prime/IPTV), CEC still blocked on hardware.
