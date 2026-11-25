# PLAN — Foyer v3 + foyer-os: big-picture UI engine, any-resolution layout, device-profile build framework

## Context

User feedback after TV testing of v2:

1. **No apps launched.** Box log: every launch → `App exited with status 127` within ~15 ms.
2. **Network settings showed no info** (Ethernet should have shown 192.168.1.123).
3. **"Focus on 1080p" is wrong.** The TV's EDID offers 640x480 … 3840x2160/4096x2160. The UI must
   use the mode the monitor reports, let the user change it, and lay out fluidly from 480p to 4K.
4. **Completely refactor the UI**: modern **Steam Big Picture / PS5** look, user-customizable,
   dynamic, fluid.
5. **Build framework** so this Alpine setup can be built for any device; a 4K-capable x86_64 board
   is coming.

### Root cause of bugs 1 + 2 (verified on box)

`/proc/<big-launcher>/environ` → `PATH=/sbin:/usr/sbin:/bin:/usr/bin`. The inittab-spawned session
never gets `/usr/local/bin`, which holds `htpc-app`, the `htpc-*` symlinks, `htpc-ctl`, `red` and
`jellyfin-desktop`. So `sh -c htpc-jellyfin` exits 127, and every `htpc-ctl net status` job fails.
That makes `res.ok == false`, so `NetworkSettings` never fills in. Over SSH (login PATH),
`htpc-ctl net status` returns `eth=192.168.1.123` fine.

Other problems found:
- Failures are silent: the toast says only "exited with an error", and failed jobs are dropped.
- `net:status` reports only the first IP. It has no iface/MAC/gateway/DNS/link speed.
- `App::init_display` forces a 16:9 letterbox. `DisplaySettings` cycles a hardcoded list of 3 modes.
  `session.conf` hardcodes 1920x1080@60, and gamescope `-W/-H/-w/-h` are pinned to it.
- Geometry mixes screen fractions (home) with hardcoded px (`ListScreen` top=170, row=font+48,
  toast at h-120, theme font sizes 22–44 px). It breaks at any size other than 1080p.
- Nothing about the "box" is reproducible: software is compiled **on** the 2 GB box by
  `install-on-box.sh`, and 1080p and the Intel GPU are hardcoded.

### Decisions (from user)
- **Keep SDL3/C++** and build our own retained-mode UI engine (no Qt/web).
- Aesthetic: **Steam Big Picture / PS5**. Top nav tabs, a hero area with background art for the
  focused app, a horizontal tile row, and a quick-access panel.
- Customization (all four): theme (colors/fonts/wallpaper/accent), in-UI **layout editor**
  (rows/tiles), **per-app artwork & metadata**, and **user-authored drop-in themes/layouts**.
- Config format: **TOML** (toml++, header-only). Importer from `layout.xml` + `config.ini`.
- **Naming**: the launcher fork is renamed **Foyer** (`JuggyMcNutty/big-launcher` → `JuggyMcNutty/foyer`).
  The OS/build framework is a separate repo, **foyer-os** (`JuggyMcNutty/foyer-os`). The `htpc-*`
  system names become `foyer-*`. Collision check: Alpine/Arch/Flathub are clear. The AUR has an
  unrelated 2018 `foyer`. GitHub has an inactive `FoyerOS/foyer-os` placeholder org, which we
  accept.

### Naming map (applied at step B0; Phase A ships on the old names)
| Old | New |
|---|---|
| repo `JuggyMcNutty/big-launcher` | `JuggyMcNutty/foyer` (GitHub redirect; README credits complexlogic/big-launcher) |
| branches `master` + `htpc` + `v2` (+ planned `v3`) | **one branch: `main`** (see branch policy) |
| binary `big-launcher` / `--overlay` | `foyer` / `foyer --overlay` |
| C++ namespace `BL::`, CMake `EXECUTABLE_TITLE` | `Foyer::`, `foyer` |
| this project dir (not a git repo) + `htpc-config/` + `htpc-setup/` | repo `JuggyMcNutty/foyer-os` (pins `foyer` as submodule/tag) |
| `htpc-ctl`, `htpc-app <id>`, `htpc-<app>` wrappers | `foyer-ctl`, `foyer-app <id>` |
| `/etc/htpc/`, `/run/htpc-session`, `/opt/htpc/launcher` | `/etc/foyer/`, `/run/foyer`, packaged under `/usr` (`/usr/bin/foyer`, `/usr/share/foyer/`) |
| logs `~/.local/share/big-launcher/` | `$XDG_STATE_HOME/foyer/` (`/var/log/foyer/` for the session) |
| APKs | `foyer`, `foyer-session`, `foyer-update`, `foyer-sdl3_image`, `foyer-red`, `foyer-jellyfin-desktop` |
| images | `foyer-os-<profile>-<ver>.img.zst` |

### Branch policy (applies to `foyer` and `foyer-os`)
- **Only `main`** exists on GitHub. It is the default and protected branch; work is committed
  there directly, with short-lived local topic branches merged/rebased the same day and never
  pushed long-term.
- **Consolidation (start of B0):**
  1. Rename `v2` to `main` (`git branch -m v2 main`, push `main`, set it as the GitHub default).
  2. Tag the history being retired first: `archive/htpc-v1` (from `htpc`) and `upstream-2025-08`
     (from `master` = complexlogic HEAD). Nothing is lost, and rollback is `git checkout
     archive/htpc-v1`.
  3. Delete the remote branches `fork/htpc`, `fork/master` and `fork/v2`, then delete the local
     `htpc`/`master`.
- **Upstream** is tracked only as the `origin` remote (complexlogic). It is pulled ad hoc into
  `main` if upstream ever moves again, and there is no mirror branch.
- **No `v3` branch**: the rewrite lands on `main` in steps. The box keeps a known-good build via
  release tags (`v2.x` = today's shipping state, `v3.0.0` = rewrite) and the APK version, not
  via branches.
- **Releases/rollback** = git tags + GitHub release assets. `foyer-update` can pin a tag.

**Migration:** `foyer-session` ships compat symlinks (`htpc-ctl`→`foyer-ctl` and
`/etc/htpc`→`/etc/foyer`) plus the TOML importer, so the current box keeps working until it is
re-provisioned.
- Build: **device profiles → APKs → flashable image**, **x86_64 only** for now. APKs are
  **unsigned** and installed with `--allow-untrusted`. They are published as **GitHub release
  assets** (no hosted repo). They are built in **GitHub Actions** and locally by the same script,
  inside an **Alpine minirootfs sandboxed with bubblewrap**: no podman/docker, no root, no daemon.
- **Never exec on the host** (outside the distrobox) without explicit user approval. All build
  tooling runs inside the dev distrobox.
- **Two libc targets**: **musl (Alpine 3.24)** and **glibc (Debian)**.
  - Foyer is built and tested on both.
  - foyer-os profiles pick `BASE=alpine|debian`.
  - Glibc builds are compiled on the **oldest supported Debian (bookworm, glibc 2.36)**. glibc is
    backward-compatible, so the resulting `.deb`/tarball runs on newer glibc distros (trixie,
    Ubuntu 24.04+, Arch, Fedora).
  - Debian images use **trixie** (newer gamescope, PipeWire and Qt6).
  - Why glibc: Widevine/DRM browsers (Prime and Netflix), Steam and other glibc-only apps, and
    the future 4K board. Alpine stays the lean option for low-RAM boxes.

---

## Approach

### Phase A — hotfix on the current shipping code (`v2`, becomes `main` in B0; ship today)
- `session.sh`: `export PATH=/usr/local/sbin:/usr/local/bin:$PATH HOME=/root`, plus
  `XDG_STATE_HOME`/`XDG_CONFIG_HOME`.
- `App` ctor: prepend `/usr/local/bin` to `PATH` if it is missing (defensive).
- `Process::spawn`: redirect the child's stdout/stderr to `$XDG_STATE_HOME/htpc/apps/<slug>.log`.
  If an app exits fast (<3 s, non-zero), the toast shows the cause: `127 → "command not found:
  htpc-jellyfin"` plus the last stderr line.
- `JobQueue`: log failed jobs at warn with the command, exit code and output tail.
- `htpc-ctl net status`: one TAB line per interface:
  `iface type state ip/cidr mac gw dns speed`. `NetworkSettings` shows them all. It must not
  reject the whole job on a partial failure.
- **Remove the duplicate YouTube tile**: Red *is* our YouTube client. Delete the `YouTube` entry
  from `htpc-config/layout.xml` and the `youtube)` case + `htpc-youtube` symlink from
  `htpc-app`/`install-on-box.sh`. Rename the Red tile's title to **YouTube** with the Red icon. The
  `youtube.com/tv` chromium fallback moves inside the wrapper (`red --tv || chromium … /tv`),
  so there's no second tile.
- Verify on the box: each tile launches, and Network shows eth0 details.

### Phase B — the UI engine (`src/ui/engine/`, replaces `ListScreen`/`TextSprite`/ad-hoc geometry)
A small retained scene graph that is redrawn only when something is dirty or animating (the
dirty-flag loop is kept).

- **Units & scaling**: everything is in **dp** (1 dp = 1 px at 1080p).
  `px = dp * (render_h/1080) * ui_scale`. Safe-area insets come from `overscan`. Text is rasterized
  at the real pixel size, so it stays crisp at 4K. Window-size or mode changes trigger
  `Engine::relayout()` and re-rasterize the glyph caches.
- **Breakpoints** (short edge): `xs<600` (480p), `sm<900` (720p), `md<1600` (1080p), `lg≥1600`
  (1440p/4K). Themes and layouts can override metrics per breakpoint (tile count per row, hero
  height, whether the nav collapses into icons).
- **Aspect**: remove the forced 16:9 letterbox. Layout reflows for 4:3/16:10/21:9.
- **Nodes**: `Node` (transform: pos/scale/opacity, clip, children, dirty) with subclasses
  `Rect` (rounded, border, shadow via 9-slice), `Image` (async-loaded, cover/contain), `Text`
  (wrapping, ellipsis), `Blur` (cached `fast_gaussian_blur` of the background art).
  Containers: `Row`, `Column`, `Stack`, and `Scroller` (smooth scroll that keeps focus in view).
- **Layout**: a minimal flex model (direction, gap, padding, grow, align). Sizes are in dp or %.
- **Motion**: extend `Anim` with **springs** (critically damped) and property bindings
  (`node.scale.to(1.08)`). Focus moves animate scale, glow and position. Background art cross-fades.
  Tab/screen transitions slide and fade. A per-theme `motion.speed` sets the speed, and
  "reduce motion" turns it off.
- **Focus engine**: spatial D-pad navigation between focusable nodes. Each row remembers its focus,
  and focus is restored on back. It is fed by the existing `Action`/`ActionMapper`/evdev/gamepad.
- **Assets**: `AssetCache` with async decode on the `JobQueue` worker pool. It enforces an LRU
  **VRAM/RAM budget** (from the profile: 2 GB box → small budget, ~96 MB). SVGs are rasterized at
  the target px size.
- **Render resolution**: the profile/settings can render the UI below output resolution (gamescope
  `-w/-h` < `-W/-H`, FSR/linear upscale), e.g. 4K output with a 1080p UI on the N3350.

### Phase C — screens & customization (Big Picture style)
- **Shell**: a top bar (tabs from the layout, plus clock, net/audio/BT status icons and a
  notification dot), the content area and a toast/notification layer.
- **Home**: a hero area with blurred, darkened background art of the focused tile, and a large title
  with a subtitle. Below it are horizontal tile rows. The focused tile is larger. Rows scroll
  vertically when there are several.
- **Library/Apps tab**: a grid of all apps. **Settings tab**: the same pages, rebuilt on the engine
  (Audio, Display, Network, Bluetooth, System, Power, Appearance, Layout).
- **Quick-access panel** (overlay process kept: `--overlay` + `GAMESCOPE_EXTERNAL_OVERLAY`). It
  slides in from the right with volume, "close app", "back home", power and display options.
- **OSK**: rebuilt on the engine, with dp layout and a full-width bottom sheet.
- **Config files (TOML)**, searched in order: user `/etc/foyer/` → theme dir → built-in defaults.
  - `settings.toml`: behaviour (sound, screensaver, gamepad, hotkeys, ui_scale, overscan,
    active theme).
  - `layout.toml`: `[[tab]] → [[tab.row]] → [[tab.row.tile]]`. Each tile has an `app` reference
    or an inline command.
  - `apps.d/*.toml`: one per app. Default lineup: **Jellyfin, YouTube (Red), Prime Video,
    Twitch, IPTV** (one YouTube entry).
    Fields: id, title, subtitle, command, env, args, `icon`, `tile`
    art, `hero` art, `background` color, `logo`. This is per-app artwork & metadata.
  - `themes/<name>/theme.toml` + assets: colors (bg, surface, accent, text, …), fonts, metrics per
    breakpoint, motion, wallpaper (image | color | "focused-art"). Search path is built-in
    `/usr/share/foyer/themes` then user `/etc/foyer/themes`, so themes are drop-in and shareable.
  - A one-shot importer converts the existing `layout.xml`/`config.ini` → TOML on first run.
- **In-UI editors**: the Appearance page (theme picker, accent, wallpaper, ui scale, reduce
  motion; live preview) and the Layout editor (add/remove/reorder tabs, rows and tiles, tile size,
  pin to Home, edit app title/command/art via OSK and a file picker over `/etc/foyer/art`). Changes
  are saved atomically with `.bak` (the existing writer strategy is reused for TOML).
- **Display settings**: list the **real** modes (from `htpc-ctl display modes`, which reads the
  DRM connector modes and the preferred mode, plus SDL), the refresh rate and the UI render
  resolution. Apply → session restart → **15 s keep/revert** countdown (revert is stored in
  `session.conf.prev`, and session.sh reverts if not confirmed). The default is the monitor's
  **preferred** mode, not 1080p.

### Phase D — device-profile build framework (new repo `JuggyMcNutty/foyer-os`)
Repo layout: `profiles/`, `aports/`, `session/` (from `htpc-config/`), `scripts/`, and `foyer/`
(submodule pinned to a tag), plus `.github/workflows/`. This project dir becomes the repo's
working copy. `AGENTS.md` and `hardwarefacts.md` move in too, and `plans/` stays.
- **Profiles** `profiles/<device>.sh`, POSIX-sourced. Fields: `ARCH=x86_64`,
  `KERNEL=linux-lts`, `GPU_PKGS` (`mesa-vulkan-intel mesa-va-gallium intel-media-driver …`),
  `FIRMWARE_PKGS`, `NET`/`WIFI`/`BT`, `BOOT=uefi|bios|both`, `DISK=mmcblk0|nvme0n1|sda`,
  `IMG_SIZE`, `RENDER_MAX` (e.g. 1920x1080 on the N3350, native on the 4K board), `ASSET_BUDGET_MB`,
  `APPS` (subset), `HOSTNAME`. Ship `ideapad-120s.sh` (current box) and `generic-x86_64.sh`
  (template for the new 4K board).
- **APK packages** `aports/` (APKBUILDs):
  - `foyer` (the launcher, from the submodule tag)
  - `foyer-sdl3_image` (not packaged on Alpine)
  - `foyer-red`, `foyer-jellyfin-desktop` (built from pinned upstream tags)
  - `foyer-session`: session.sh, `foyer-ctl`, `foyer-app`, `/etc/foyer` defaults, inittab hook,
    openrc deps (seatd, udev, xwayland, hwdata, pipewire, wireplumber). It sets PATH properly, so
    the bug class from Phase A goes away.
  - `foyer-update`: fetches the latest GitHub release `.apk`s and runs `apk add --allow-untrusted`.
- **Build sandbox** `scripts/alpine-env.sh` (shared by all scripts). Arch is native x86_64, so
  there is no cross-compiling: the build runs on Alpine's own musl toolchain and libs.
  - It downloads `alpine-minirootfs-3.24.x-x86_64.tar.gz` from dl-cdn and **verifies sha256** (the
    pinned version and hash are in `scripts/alpine.lock`), then unpacks it to
    `.cache/alpine-root/`. The rootfs is reused across runs and refreshed by `apk upgrade`.
  - It runs commands with `bwrap --bind .cache/alpine-root / --bind $PWD /work --dev /dev
    --proc /proc --tmpfs /tmp --ro-bind /etc/resolv.conf /etc/resolv.conf --unshare-user --uid 0
    --gid 0 --unshare-pid --die-with-parent --chdir /work <cmd>`.
  - `bwrap` and unprivileged userns are **already available** in the dev distrobox (verified).
  - CI uses the same `alpine-env.sh` on `ubuntu-latest` (bwrap from apt), so local and CI
    builds can't drift.
- **Build script** `scripts/build-apks.sh`: inside the sandbox, `apk add alpine-sdk` and then
  `abuild -r` per `aports/*/APKBUILD`, in dependency order (`foyer-sdl3_image` goes first into a
  local temp index). It signs with a throwaway key, since installs are `--allow-untrusted`.
  Output goes to `out/apks/x86_64/`.
- **Image script** `scripts/make-image.sh <profile>`: **rootless, with no loop devices or mounts**.
  - Inside the sandbox, `apk --root /work/out/rootfs-<profile> --initdb add alpine-base $KERNEL
    $GPU_PKGS …` installs from the official mirrors, then our local `.apk`s with
    `--allow-untrusted`.
  - It writes `fstab`, `interfaces` (DHCP on every wired iface), inittab, and
  openrc runlevels. It sets the root SSH key from `FOYER_SSH_PUBKEY` and the bootloader
    (systemd-boot for UEFI or syslinux for BIOS, per profile).
  - Assembly: the root partition is built with `mkfs.ext4 -d rootfs` (no mount needed) and the
    ESP with `mkfs.vfat` + `mcopy` (mtools). `sfdisk` writes the GPT layout to an image file, and
    `dd conv=notrunc` places both partitions at their offsets. BIOS images also get syslinux
    `gptmbr.bin` plus `extlinux`-equivalent install via `syslinux --offset` on the image. All
    tools come from Alpine packages inside the sandbox, so nothing new goes on the dev box.
  - Output is `out/foyer-os-<profile>-<ver>.img.zst`, flashed with `dd` from a live USB.
- **Provision path** `scripts/provision.sh <profile>`: on an existing stock Alpine box (like
  today's), it applies the same package set and our APKs. This replaces `install-on-box.sh` and
  `push-to-box.sh`. Nothing compiles on the target any more.
- **CI** `.github/workflows/release.yml` in **foyer-os**. On tag `v*`, it runs `build-apks.sh` and
  `make-image.sh` for each profile via the same bwrap sandbox on `ubuntu-latest`, plus a QEMU
  boot smoke test and attaches them to the foyer-os GitHub Release.
  The `foyer` repo has its own CI: build + unit tests on **Alpine (musl) and Debian bookworm (glibc)**.

### Phase E — glibc / Debian target (after the Alpine image path is green)
- **Sandbox**: `scripts/debian-env.sh` mirrors `alpine-env.sh`. It builds rootless rootfs with
  `mmdebstrap --mode=unshare` (from Debian's own mmdebstrap inside a bootstrap Alpine sandbox,
  so nothing is installed in the distrobox). Rootfs: `bookworm` for building, `trixie` for images.
  It uses the same bwrap invocation. CI uses `ubuntu-latest` + bwrap.
- **Packaging**: `debian/` packaging (`dpkg-buildpackage -us -uc`, unsigned like the APKs) for
  `foyer`, `foyer-session`, `foyer-update`, `foyer-red` and `foyer-jellyfin-desktop`.
  - SDL3_image comes from trixie where packaged; on bookworm we bundle it.
  - Bookworm lacks SDL3 and Qt 6.11, so glibc-portable artifacts **statically bundle SDL3/
    SDL3_image/SDL3_ttf** into foyer. Red and jellyfin-desktop are built against trixie only.
  - Outputs: `out/debs/{bookworm,trixie}/`, plus `foyer-<ver>-x86_64-glibc.tar.zst` (portable
    launcher, bookworm-built).
- **Init-agnostic session** (`foyer-session`):
  - **OpenRC**: inittab tty1 respawn + openrc deps (today's path).
  - **systemd**: `foyer-session.service` on tty1 (`TTYPath=/dev/tty1`, `PAMName=login`,
    `User=root` for now) + `seatd`/logind, PipeWire as user services.
  - `session.sh` is shared. It detects the init and only differs in service start.
- **`foyer-ctl` backend abstraction**: power (`loginctl`/`systemctl` vs OpenRC `poweroff`),
  network (ifupdown-ng vs **NetworkManager** via `nmcli`, chosen on Debian since it also covers
  WiFi), and services (`rc-service` vs `systemctl`). A small `backend_<init>.sh` is sourced at the top.
- **Profiles**: `BASE=alpine|debian` + `SUITE=trixie`. Package lists per base
  (`profiles/base/{alpine,debian}.pkgs`) map logical names to distro packages (e.g. `gpu-intel` →
  `mesa-vulkan-intel` vs `mesa-vulkan-drivers intel-media-va-driver`).
- **Images**: `make-image.sh` branches on `BASE`. The Debian rootfs comes from `mmdebstrap`
  (trixie + our debs), with the same rootless assembly (`mkfs.ext4 -d`, mtools, sfdisk) and
  systemd-boot / syslinux. Output: `foyer-os-<profile>-debian-<ver>.img.zst`.
- **Provision**: `provision.sh` supports a stock Debian trixie install (apt + our debs).

---

## Files to modify / create

Phase A
- `htpc-setup/install-on-box.sh` (session.sh PATH/XDG), `htpc-config/bin/htpc-ctl` (net status,
  display modes)
- `big-launcher/src/core/app.cpp`, `src/platform/process.{hpp,cpp}`, `src/jobs/job_queue.cpp`,
  `src/screens/settings/network.cpp`

Phase B0 (rename)
- GitHub: rename the fork to `foyer`, create `foyer-os`, `git init` this project dir → push
- `foyer`: CMakeLists (`EXECUTABLE_TITLE`), `config/*.in`, `BL::`→`Foyer::` across `src/` + `tests/`,
  `App::open_quick_menu` exe name, log path, README/FORK.md
- foyer-os: move `htpc-config/` → `session/`; `htpc-ctl`→`foyer-ctl`, `htpc-app`→`foyer-app`;
  layout commands are updated by the importer

Phase B/C (`foyer` repo, on `main`)
- New: `src/ui/engine/{node,layout,text,image,rect,blur,scroller,focus,units,engine}.{hpp,cpp}`,
  `src/core/{toml_config,app_registry,theme_loader,importer}.{hpp,cpp}`, `src/external/toml.hpp`
- Rewrite: `src/screens/{shell,home,library,quick_menu}.*`, `src/screens/settings/*`
  (+ `appearance.*`), `src/ui/text_input.*`, `src/render/theme.*`
- Modify: `src/core/app.*` (display init, relayout on mode change, no letterbox),
  `src/ui/anim.*` (springs), `src/render/renderer_sdl.*` (clip stack, 9-slice, texture budget)
- Remove: `src/ui/{list_screen,text_sprite,status_bar,shapes}.*`, `src/screens/home.*` (old)
- Default theme: `foyer/data/themes/default/` (+ `data/themes/light/`), `data/layout.toml`,
  `data/apps.d/*.toml`
- Tests: `tests/test_core.cpp` gains TOML round-trip, importer, flex layout, dp/breakpoint math,
  and focus nav

Phase D
- New (foyer-os): `profiles/`, `aports/`, `scripts/{build-apks,make-image,provision}.sh`, `README.md`
- New (foyer-os): `.github/workflows/release.yml`. New (foyer): `.github/workflows/ci.yml`
- `session/` feeds `aports/foyer-session/`. `htpc-setup/` is retired after cutover.
- `AGENTS.md` and `hardwarefacts.md`: drop the "1080p focus" wording and document profiles.

Phase E
- New (foyer-os): `scripts/debian-env.sh`, `scripts/build-debs.sh`, `debian/<pkg>/` packaging,
  `profiles/base/{alpine,debian}.pkgs`, `session/backend_{openrc,systemd}.sh`,
  `session/systemd/foyer-session.service`
- New (foyer): CMake option `FOYER_BUNDLE_SDL` (static SDL3 family for portable glibc builds)
- Modify: `make-image.sh`, `provision.sh`, `foyer-ctl`, `session.sh`, `release.yml` (matrix over
  base × profile)

## Reuse
- `JobQueue` (`src/jobs/job_queue.cpp`): async shell jobs and the asset decode worker
- `Process` (`src/platform/process.cpp`): pidfd reap and group kill
- `Anim` (`src/ui/anim.cpp`): extended with springs, not replaced
- `ActionMapper`, `EvdevGlobal`, the CEC stub, `ScreenStack` semantics, and the overlay mechanism
  (`App::open_quick_menu`)
- `Config` atomic write + `.bak` logic (`src/core/config.cpp`): reused for the TOML writer
- `SVGRasterizer`/`load_surface` (`src/render/image.cpp`), `fast_gaussian_blur_template.h`, `Font`
  (`src/render/text.cpp`), `RendererSDL`
- `htpc-ctl` (audio/wifi/bt/sys/power groups are kept; net/display are extended)
- `install-on-box.sh` package list + openrc wiring: the source of truth for `foyer-session` deps
  and the image builder

## Steps
- [x] **A1** session.sh PATH/HOME/XDG + App PATH guard; drop duplicate YouTube tile (Red = YouTube);
      push to box; confirm tiles launch
- [x] **A2** per-app stderr log + meaningful failure toasts; JobQueue failure logging
- [x] **A3** `htpc-ctl net status` per-interface; Network page shows eth0 ip/mac/gw/dns/speed
- [x] **B0** branch consolidation: archive tags (`archive/htpc-v1`, `upstream-2025-08`), `v2`→`main`
      as default, delete `htpc`/`master`/`v2` on GitHub + locally (Phase A hotfix commits land
      first, so they're on `main`); then rename: fork → `foyer`, create `foyer-os` repo (git init this dir, `foyer` as
      submodule), `BL::`→`Foyer::`, binary/paths/scripts per the naming map, compat symlinks;
      build + 7 tests green
- [x] **B1** tag `v2.0.0` on `main` (pre-rewrite rollback point); vendor toml++; `units` (dp, breakpoints, safe area) + tests
- [x] **B2** Node tree, Rect/Text/Image, flex layout + tests; renderer clip stack/9-slice
- [x] **B3** springs + property tweens; Scroller; focus engine + tests
- [x] **B4** AssetCache (async decode, LRU budget), Blur node
- [x] **B5** remove letterbox; relayout on display-mode change; render at 480p/720p/1080p/4K with
      no clipped or overlapping UI (screenshots via `--screenshot` debug flag)
- [x] **C1** TOML settings/layout/apps.d/theme loaders + importer from xml/ini + round-trip tests
- [x] **C2** Shell (top nav, status icons, toasts) + Home (hero + rows) + Library
- [x] **C3** Settings pages on the engine; Display with real modes + keep/revert; Appearance page
- [x] **C4** Layout editor + per-app metadata/art editor; OSK rebuild
- [x] **C5** Quick-access overlay rebuilt; default + light themes; delete old UI code
- [x] **D1** APKBUILDs (foyer, foyer-sdl3_image, foyer-red, foyer-jellyfin-desktop, foyer-session, foyer-update)
- [ ] **D2** `alpine-env.sh` (minirootfs + sha256 lock + bwrap) and `build-apks.sh` — green locally
      in the distrobox
- [ ] **D3** profiles (`ideapad-120s`, `generic-x86_64`) + `provision.sh`; re-provision the box
- [ ] **D4** rootless `make-image.sh` (mkfs.ext4 -d / mtools / sfdisk) → bootable raw image;
      QEMU boot-test (UEFI + BIOS) in CI, and locally via Alpine's `qemu-system-x86_64` +
      `ovmf` inside the sandbox (TCG, no KVM needed)
- [ ] **D5** GitHub Actions release workflow (foyer-os) + CI (foyer); `foyer-update` pulls from releases
- [ ] **D6** docs: AGENTS.md, hardwarefacts.md, foyer README/FORK.md, foyer-os README
- [ ] **E1** `debian-env.sh` (rootless mmdebstrap bookworm/trixie in bwrap); foyer CI on bookworm
      green; `FOYER_BUNDLE_SDL` portable tarball
- [ ] **E2** `debian/` packaging for foyer, foyer-session, foyer-update, foyer-red,
      foyer-jellyfin-desktop; `build-debs.sh`
- [ ] **E3** init-agnostic session (OpenRC + systemd unit) + `foyer-ctl` backends (OpenRC/ifupdown
      vs systemd/NetworkManager)
- [ ] **E4** `BASE=debian` in profiles + per-base package maps; `make-image.sh` Debian path;
      `provision.sh` on stock trixie
- [ ] **E5** CI matrix (alpine/debian × profiles), QEMU boot both; release attaches .apk + .deb +
      tarball + images

## Verification
- **Phase A**: on the box, launch every tile (Jellyfin, YouTube via Red, Prime, Twitch, IPTV). The log
  should show non-127 statuses and the apps should appear on TV. The Network page should show
  eth0 details. A deliberately broken command should show a descriptive toast.
- **Unit tests** (doctest, run on the dev distrobox and in the Alpine bwrap sandbox): TOML/importer round-trips, flex
  layout results, dp/breakpoint math, focus-nav graph, plus the existing 7 tests.
- **Resolution matrix**: run the launcher in nested gamescope / an SDL window on the dev machine at
  640x480, 1280x720, 1920x1080, 2560x1080 (21:9), 3840x2160. Take screenshots with `--screenshot`
  and review them for clipping and overlap. On the box, switch modes through Display settings,
  including 4K output with a 1080p UI, and test that keep/revert works.
- **Perf on the N3350**: home idle at ~0% CPU (dirty loop), a steady 60 fps during focus
  animations (frame-time log in `--debug`), launcher RSS < 300 MB.
- **Customization**: switch theme live, drop in a user theme under `/etc/foyer/themes/`, add, move
  and remove a tile from the couch, restart, and confirm it persisted.
- **Build framework**: `build-apks.sh` passes locally and in CI. A `make-image.sh generic-x86_64`
  image boots in QEMU (UEFI and BIOS) to the launcher. `provision.sh ideapad-120s` on the real box
  yields a working session with no on-box compilation. `foyer-update` upgrades from a foyer-os GitHub release.
- **glibc (Phase E)**: the portable tarball (bookworm-built) runs on trixie, Ubuntu 24.04 and Arch
  (dev distrobox) — checked with `objdump -T | grep GLIBC_` showing a max of 2.36. A
  `foyer-os-generic-x86_64-debian` image boots in QEMU (UEFI + BIOS) to Foyer via systemd. In
  Settings, power, network (NetworkManager) and audio work. Chrome/Widevine plays a DRM test
  stream (Prime check).
- **Rename (B0)**: the fork URL redirects. `foyer` builds, and tests pass. The box still works through
  the compat symlinks (`htpc-ctl net status` → foyer-ctl). The old `layout.xml` imports with
  `foyer-app` commands.

## Resolved
- Two libc targets: musl (Alpine 3.24) and glibc (Debian). Builds run on bookworm for the widest
  glibc compatibility, and images use trixie.
- Build framework, CI and releases live in the separate repo **`JuggyMcNutty/foyer-os`**, with
  `foyer` pinned as a submodule.
