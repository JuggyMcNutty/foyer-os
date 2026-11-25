# big-launcher v2 — full HTPC big-picture frontend

## Context
The `htpc` branch of our fork (github.com/JuggyMcNutty/big-launcher) is a ~4.5k-LOC C++23/SDL3
Roku-style launcher. It boots on the box (Alpine/OpenRC/musl, gamescope 3.16 + Xwayland, 1080p60,
Celeron N3350, 2 GB RAM, launcher RSS fine, ~1.3 GB free at idle). We want a real couch frontend:
every PC function reachable from the sofa, usable with keyboard, gamepad and (later) a TV remote over CEC.
The current codebase isn't good enough to build that on, so v2 is a **heavy rewrite**. We keep the
visual language (sidebar plus card grid), the `layout.xml`/`config.ini` formats, and a few leaf modules.

### Decisions (from user)
- Rewrite on a new **`v2` branch**. `htpc` keeps shipping until v2 reaches parity, then v2 becomes default.
- Features in scope: **quick-menu overlay**, **on-screen keyboard**, **status bar + notifications**, **in-UI layout editor**.
- Settings in scope: **Audio + Display**, **Network + Bluetooth**, **System + Power**, **Launcher prefs**.
- Inputs: **2.4G keyboard/air-mouse**, **gamepad**, **HDMI-CEC** (backend built behind a flag; tested later because there is no adapter yet).
- Do a **spike for the overlay first**. If it fails, fall back to "Home = return to launcher".
- **Keep and extend** `layout.xml` + `config.ini`. The launcher must now be able to write them back.

## Code audit — findings
### Bugs
1. **Power commands do nothing**: `platform/platform.hpp` calls `systemctl`, but the box runs OpenRC.
2. **`start_process` (platform/unix.cpp)**: if `execvp` fails, the child never `_exit`s, so a second
   launcher keeps running. There's no `setsid` and children are never reaped, so zombies pile up. `process_running()` is dead code, and a single global `child_pid` is used.
3. **App lifecycle depends on window FOCUS events plus a 10 s timeout**. This is fragile under gamescope.
4. **Settings block the UI thread**: synchronous `popen`. `wifi-scan` takes 2 s, `wifi-connect` up to 20 s, and `bt-scan` also blocks.
5. **Settings are keyboard-only**: gamepad `:up/:select` drives the grid behind the settings screen, and gamepad **B = `:quit`**
   kills the launcher.
6. `SDL_FlushEvent(KEY_DOWN)` after every key drops queued input.
7. `Config::add_int/add_time` → `std::stoi` throws on a bad value, and nothing catches it.
8. `Layout` init-order mismatch. `rasterizer` is leaked. Raw `new/delete` everywhere.
9. `Menu`/`MenuEntry` own raw `SDL_Surface*`/`Texture*` but have default copy/move, so moving them inside a `std::vector` risks double-frees.
   `std::move(*unique_ptr)` anti-pattern.
10. The screen is redrawn on every vsync even when idle (~4 % CPU on N3350), and the screensaver is just a dimmer.

### Structure
`Layout` is a 784-line god class (parse + geometry + animation + input + draw). Geometry is hard-coded
(`COLUMNS=3`). Input routing is ad-hoc. Global `config`, commands are defined as macros, and the Windows paths are unused. No tests.

### Keep and reuse
- `image.cpp` (`SVGRasterizer`, nanosvg), `text.cpp` (`Font`), `sound.cpp`, `external/` (ini.h, nanosvg, blur).
- Shadow/blur pipeline (`BL::create_shadow`, `util.cpp`), `renderer_sdl.cpp` texture compositing.
- The ideas behind `clock.cpp` and `settings_screen.cpp` (rebuilt as widgets).
- The shell helper pattern (`htpc-config/bin/htpc-net`) → grows into **`htpc-ctl`**.

## Architecture (v2)
```
src/
  core/      app.cpp (main loop, dirty-flag rendering), config (ini read+write), layout_model (xml read+write)
  platform/  process.cpp (spawn/setsid/pidfd reap, kill group), power.cpp (OpenRC), sysctl.cpp (htpc-ctl IPC)
  input/     action.hpp (Up/Down/Left/Right/Accept/Back/Home/Menu/VolUp/VolDown/Mute/Text)
             sdl_keyboard.cpp, sdl_gamepad.cpp, evdev_global.cpp (non-grab Home/Vol while app is focused),
             cec.cpp (libcec, -DBL_CEC=ON)
  ui/        screen.hpp + screen_stack (push/pop, input dispatched to top screen only)
             widgets: List, Toggle, Slider, Choice, Grid, Card, Label, Toast, StatusBar, OSK
             anim.cpp (generic tweens; replaces Shift/Press queues)
  screens/   home (sidebar+grid), quick_menu, settings/{audio,display,network,bluetooth,system,power,launcher},
             layout_editor, osk_modal, confirm_dialog
  jobs/      job_queue.cpp: worker thread runs system commands, results posted to main loop via SDL user event
  render/    renderer_sdl.cpp, image.cpp, text.cpp (kept), theme.cpp (colors/fonts/geometry from config)
```
Principles: RAII everywhere (`unique_ptr` with SDL deleters), no globals (pass `AppContext&`). Input is always
mapped to **actions** before it reaches screens. Nothing blocks the UI thread. Only redraw when something is dirty or animating.

### System control backend: `htpc-ctl`
A single POSIX-sh helper on the box (supersedes `htpc-net`). Commands are line-oriented with TAB-separated output. It runs as root
inside the session. Groups:
- `audio`: `wpctl` for volume/mute/sinks/default sink.
- `display`: gamescope output mode. A resolution change rewrites the `-W/-H/-r` in `/etc/htpc/session.conf` and restarts the session. UI scale and overscan are done in-app.
- `wifi`/`bt`: existing `htpc-net` logic plus forget/disconnect/power. BT battery comes from `bluetoothctl info`.
- `net`: eth/wifi IP, DHCP or static via `/etc/network/interfaces` (ifupdown-ng).
- `sys`: hostname, timezone (`setup-timezone`), NTP sync, `apk update/upgrade` (streamed progress),
  disk/RAM/CPU temperature, uptime.
- `power`: `poweroff`, `reboot`, `echo mem > /sys/power/state` (box supports freeze/mem/disk), sleep timer.

The C++ side talks to it only through the `jobs/` queue. Streaming jobs (apk upgrade, BT scan) post progress lines.

### Overlay strategy (spike decides)
- **A (preferred):** the launcher runs as an X11 client (Xwayland) and marks a second window with
  gamescope's overlay atom (`STEAM_OVERLAY` / `GAMESCOPE_EXTERNAL_OVERLAY`). Home/Guide is caught via **evdev
  (non-grabbing)** while an app is focused. The overlay draws the quick menu, then input focus is handed back to the app.
- **B:** gamescope `--steam`-style focus control (`GAMESCOPECTRL_BASELAYER_*` atoms) to switch the base layer
  between the launcher and the app, giving "switch app" / "return home" without killing the app.
- **Fallback:** Home = SIGTERM (or SIGSTOP) the app process group and return to the launcher.

Quick-menu contents: Volume ±/mute, audio output, **Close app**, **Switch to running app**, Home, Sleep/Power, Settings.

## Steps
### Phase 0 — spike + scaffolding
- [x] Create a `v2` branch from `htpc`. Set up a CMake skeleton with the `src/` layout above, `-Werror` in CI builds, and options `BL_CEC`, `BL_EVDEV`.
- [x] **Overlay spike**: `GAMESCOPE_EXTERNAL_OVERLAY` works — a client with that env var is composited on top of the running app. Strategy **A** chosen.
- [x] evdev global input (`BL_EVDEV`); CEC stub (`BL_CEC`).
- [x] Unit-test target (doctest): ini round-trip, layout.xml round-trip, action mapping, process reaping — 7/7 pass.

### Phase 1 — core rewrite (reach parity with `htpc`)
- [x] `platform/process`: `fork` + `setsid` + `_exit` on exec failure, pidfd/SIGCHLD reaping, app state = PID alive (no focus heuristics).
- [x] `platform/power`: OpenRC commands. Remove the `systemctl` macros and all Windows code.
- [x] `core/config` read **and write** (preserve comments/order), with validated values and no throwing `stoi`.
- [x] `core/layout_model`: parse plus serialize `layout.xml` (libxml2). Menus own entries by value with RAII textures.
- [x] `input/`: action mapper for keyboard, gamepad (SDL), and hotkeys from config. Key repeat handled in the mapper (no event flushing).
- [x] `ui/` screen stack, widgets and tween engine. Dirty-rect/idle redraw.
- [x] `screens/home`: rebuild sidebar + grid from the model. Columns and margins come from theme config. Sidebar commands and power tiles.
- [x] Clock, sound clicks and dimming screensaver ported.
- [x] Parity check on the box: same layout.xml, all tiles launch, RSS ~76 MB (≤ v1).

### Phase 2 — system control
- [x] `htpc-ctl` script (in `htpc-config/bin/`). Migrate `htpc-net` into it and keep a compat symlink.
- [x] `jobs/` worker thread + SDL user-event result delivery.
- [x] Settings hub screen plus pages (audio/display/network/bluetooth/system/power/launcher) — code done, needs box test.
- [x] `install-on-box.sh`: install `htpc-ctl`, generate `/etc/htpc/session.conf`, and have `session.sh` read it.

### Phase 3 — frontend features
- [x] Status bar: network + audio (top bar, 5 s refresh). (Clock is in the sidebar; BT/badge deferred.)
- [x] Toast notifications (job results, app exited with an error).
- [x] On-screen keyboard modal (QWERTY, D-pad/gamepad friendly). Used by WiFi passwords and the layout editor.
- [x] Quick-menu overlay (strategy A, `GAMESCOPE_EXTERNAL_OVERLAY`), with global Home.
- [x] Layout editor: edit title/command (OSK), reorder, add, delete entries → saves `layout.xml`. (`.desktop` scan + colour/icon edit deferred.)
- [ ] CEC backend — **blocked**: box has no `/dev/cec*` (HD 500 doesn't expose CEC; the `libcec` apk is for a Pulse-Eight USB adapter). `BL_CEC` stub in place.

### Phase 4 — cut over
- [x] Update FORK.md and README, the `AGENTS.md` handoff and `install-on-box.sh` (build the `v2` branch).
- [ ] Make `v2` the default branch on the fork. Keep `htpc` as a tag for rollback. (Waiting on user TV visual confirm.)

## Files
- New: `big-launcher/src/{core,platform,input,ui,screens,jobs,render}/…`, `big-launcher/tests/`,
  `htpc-config/bin/htpc-ctl`, `/etc/htpc/session.conf` (generated).
- Rewritten or removed: `main.cpp`, `layout.*`, `menu*.{cpp,hpp}`, `sidebar_*`, `settings_screen.*`, `network.*`,
  `gamepad.*`, `hotkey.*`, `screensaver.*`, `clock.*`, `platform/{unix,win32}.cpp`, `platform/platform.hpp`.
- Kept (moved to `render/`): `image.*`, `text.*`, `renderer*.{cpp,hpp}`, `util.*` (shadow parts), `sound.*`, `external/`.
- Modified: `htpc-config/{layout.xml,config.ini}` (new keys), `htpc-setup/{install-on-box.sh,push-to-box.sh}`,
  `AGENTS.md`, `hardwarefacts.md`.

## Verification
- **Dev machine:** `cmake --build` with `-Werror`. Run the `ctest` unit tests (config/layout round-trip, process reaping, action mapper).
  Run under `ASAN/UBSAN` in a windowed debug mode.
- **Box, every phase:** push + build via `push-to-box.sh`. Reboot and confirm it boots unattended to the launcher. Check `ps` for zombies
  after launching/closing each app 5×. Check RSS of `big-launcher` (target < 120 MB) and idle CPU (~0 % when nothing animates).
- **Couch checklist (user on the TV):** navigate everything with the keyboard only, then with the gamepad only. Open each settings page.
  Change the volume and the output sink. Join WiFi via the OSK (once a dongle exists). Pair BT. Change resolution (with revert). Add/reorder a tile and
  reboot to check it persisted. Open the quick menu over Jellyfin and over chromium, then close or switch the app. Sleep and wake.
- **CEC:** compile-tested only until an adapter arrives.

## Risks
- The overlay depends on gamescope internals (3.16 atoms). The spike gates Phase 3's overlay work, and the fallback is defined.
- Resolution change needs a session restart, which is why it's behind confirm-or-revert.
- Write-back must not corrupt hand-edited config: back up to `*.bak`, and use atomic rename on write.
