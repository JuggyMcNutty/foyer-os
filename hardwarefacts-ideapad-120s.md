# HTPC Mini PC — Hardware Facts

> Source of truth for the box at `192.168.1.123` (ssh alias: `htpc`).
> Verified via SSH on 2026-11-24 (fresh install, nothing installed yet beyond base).
> Re-verify with the commands in the [Verification](#verification) section before trusting stale values.

## TL;DR

Repurposed **Lenovo ideapad 120S-11IAP laptop/tablet motherboard** (model 81A4) in a mini-PC enclosure — no battery, no internal screen, AC-powered, headless via HDMI.

- **CPU:** Intel Celeron N3350 — 2 cores / 2 threads, 1.10→2.40 GHz, SSE4.2 only (**no AVX**)
- **RAM:** 2 GB DDR4 (soldered, fixed) + 3.5 GB swap on eMMC
- **Storage:** 32 GB eMMC (24.5 GB usable for OS) — empty 2.5" SATA port, empty microSD slot
- **GPU:** Intel HD Graphics 500 (i915, Gen 9) — **HDMI out directly on the motherboard**, connected to a **Toshiba 4K TV**. The connector reports modes from 640x480 up to 3840x2160 / 4096x2160 (EDID, `foyer-ctl display modes`); preferred mode is 1920x1080@60. HDMI 1.4 means 4K is limited to 30 Hz — no HDR
- **Audio:** Realtek ALC269VC (3.5mm speaker/HP + mics) + HDMI/DP audio
- **Network:** no Wi-Fi; USB-C Gigabit Ethernet (Realtek r8152 adapter) — **plugged directly into the board's USB port** (the temporary Nintendo hub has been removed)
- **Boot:** UEFI, GRUB, Alpine `linux-lts` 6.18.65

## Identity / DMI

The DMI strings are the **donor laptop's** (Lenovo ideapad 120S-11IAP, a 12" 2-in-1 from 2018) — the board was converted into a mini-PC chassis.

| Field | Value |
|---|---|
| Product | Lenovo ideapad 120S-11IAP |
| Internal product name | `81A4` |
| SKU | `LENOVO_MT_81A4_BU_idea_FM_ideapad120S-11IAP` |
| Serial (product/board/chassis) | `YD04NV8T` |
| Board | `LNVNB161216` (rev `SDK0J91216 WIN`) |
| BIOS | LENOVO `6GCN26WW`, dated 03/08/2018 |
| Chassis type | 10 (Other) |
| UUID | `505bc2c0-8d81-2018-0614-122240000000` |

## CPU

- **Intel(R) Celeron(R) CPU N3350** @ 1.10 GHz base — Gemini Lake, 14 nm, 6 W TDP
- 2 cores / 2 threads (no hyperthreading)
- Burst up to ~2.4 GHz (`nonstop_tsc`, `tsc_known_freq` present — good for timers)
- SIMD ceiling: **SSE4.2**. No AVX / AVX2 / AVX-512 → some optimized codec paths and prebuilt binaries fall back to scalar/SSE; ffmpeg/chromium/mpv all work fine
- AES-NI + SHA-NI present (TLS is fine)
- VT-x + EPT (vmx/ept) — virtualization available if ever needed
- Passive-cool design; ~38 °C at idle (coretemp)

## RAM

- **2 GB total** (~1.8 GiB visible), DDR4, soldered — no upgrade path
- 3.5 GB swap on `/dev/mmcblk0p2` (eMMC-backed, priority −2) — works, but eMMC swap is slow; keep resident set small
- Practical budget: base OS ~150 MB, Gamescope ~100–200 MB, PipeWire ~50 MB → **~1 GB for one app at a time**. Don't stack two Electron/browser-class apps.

## Graphics

- **Intel HD Graphics 500** (PCI `0000:00:02.0`, device `8086:5a85`)
- i915 driver identifies it as "broxton" Gen 9, stepping C0 (Gemini Lake iGPU)
- DMC firmware v1.7 loaded (from `linux-firmware-i915`)
- Vulkan via ANV (`mesa-vulkan-intel`), OpenGL 4.3/4.5 — fine for Gamescope + compositing
- **Display output: `card1-HDMI-A-1`** — HDMI cable plugs **directly into the motherboard**; no dock or adapter in the chain. Display: **Toshiba 4K TV** ("TSB - TOSHIBA-TV" per EDID, with colorimetry block)
  - EDID modes (re-checked 2026-11-24 via /sys/class/drm): 1920x1080 (preferred), 4096x2160, 3840x2160, 1280x720, 1024x768, 800x600, 720x576, 720x480, 640x480 — 4K only at 24/30 Hz over HDMI 1.4; no HDR
  - 720p and lower also available if the TV misbehaves
- Internal eDP panel (from the laptop) is not present: `failed to retrieve link info, disabling eDP` — expected for the conversion
- `renderD128` + `card1` (i915); a `simpledrm` framebuffer is also created early in boot (harmless)

## Audio

- PCI `0000:00:0e.0` — Intel HDA controller, bound to i915 (HDMI audio)
- Codec: **Realtek ALC269VC**
  - line-out pin 0x14 (type: speaker), headphone 0x15, internal mic 0x12, mic 0x18
  - In practice: 3.5mm jack(s) on the back of the box for analog out; HDMI/DP audio for the TV
- HDMI/DP audio: three PCM endpoints registered (pcm 3, 7, 8) — PipeWire should surface HDMI + analog profiles
- No HDMI ARC/eARC (HDMI 1.4) — audio goes to the TV, nothing back

## Storage

| Device | What | Layout / size | Notes |
|---|---|---|---|
| `/dev/mmcblk0` | 32 GB eMMC module, model `DF4032` (Samsung, CID `45010044…`) | p1: 511 MB FAT `/boot/efi` · p2: 3.5 GB swap · p3: 24.5 GB ext4 `/` | eMMC wear: prefer tmpfs for scratch (already: `/tmp`, `/run`), avoid heavy local logging |
| (none) | — | — | the generic USB mass-storage device was on the (now-removed) Nintendo hub; `/dev/sda` no longer appears |
| SATA | AHCI controller `0000:00:12.0` | **empty** | 2.5" SATA bay available for a future SSD |
| microSD | SDHCI controller `0000:00:1c.0` (`8086:5acc`) | no card | usable for media if needed |

## I/O & USB layout

- **HDMI:** direct to the motherboard (native port on the board) → TV
- **Power:** mains directly to the board (no battery in the conversion)
- **USB:** internal xHCI, bus 1 (SS-capable, USB-C Gen 1 5 Gbps) + bus 2 (HS)

### Permanent / target setup

- **Realtek USB-C Gigabit LAN adapter** (`r8152`) — plugged **directly** into the board's USB port → `eth0`
- 2.4 GHz wireless receivers ("Compx", "Telink" — keyboard/mouse/remotes) plugged directly

### Removed

- **Nintendo CRD-001 USB-C hub/dock** (id `057e:200c`) — **removed**. The r8152 adapter and the 2.4 GHz receivers now plug **directly** into the board's USB port. (The hub's generic mass-storage device is gone with it.)

No Wi-Fi/BT radios. No USB-A ports visible on the board.

## Power & thermals

- **Mains only**: `/sys/class/power_supply/ADP1` (`type=Mains`) — no battery in the conversion
- coretemp on `hwmon0` (38 °C at idle, 2026-11-24)
- 6 W-class SoC → quiet, low-draw in a TV stand; no fans to worry about (passive)

## Network

- `eth0` = Realtek r8152 over USB, MAC `98:fc:84:e2:0a:4f`
- **DHCP on 192.168.1.0/24 → 192.168.1.123**; IPv6 SLAAC (`fd11:c69c:e3d4::/64`)
- Managed by **ifupdown-ng** (`/etc/network/interfaces`)
- Router: `192.168.1.1` (assumed; verify if it matters)

## Kernel & boot

- `linux-lts` **6.18.65-0-lts** (Alpine 3.24.4)
- UEFI boot via `grub-efi`, root on `/dev/mmcblk0p3` (`UUID=126ea173-d64c-476e-9c1e-49ebab21679f`)
- Boot args: `ro quiet rootfstype=ext4 modules=sd-mod,usb-storage,ext4`
- Firmware packages installed: `linux-firmware-intel`, `-i915`, `-lenovo`, `-rtl_nic`, `-dell`, `-hp`

## Software baseline (fresh install, 2026-11-24)

> **Note:** this was the state at fresh install. The box now runs the full HTPC stack
> (gamescope + PipeWire + big-launcher v2, ~470 packages). See AGENTS.md for the current state.

- **Alpine 3.24.4**, OpenRC init (BusyBox), musl
- 70 packages total: base system + `openssh-server`, `ntpd`, `acpid`, `crond`, `htop`, `lsof`, `tmux`, `doas`
- Running services: `sshd`, `ntpd`, `acpid`, `crond`
- **No GUI, no Wayland, no Mesa/Vulkan, no PipeWire yet**
- SSH: key auth set up from the dev machine (see AGENTS.md); root password auth still active (password not stored in git)

### Useful Alpine repo facts (v3.24, x86_64) — all packaged, no manual builds

- `gamescope` (community), `pipewire` + `pipewire-openrc` + `pipewire-pulse-openrc` (community)
- `mesa`, `mesa-vulkan-intel` (ANV), `vulkan-tools`, `libva`, `libva-intel-driver` (main)
- `mpv`, `mpv-mpris`, `mpvpaper`, `yt-dlp`, `ffmpeg` (community)
- `chromium`, `firefox` (community), `weston` (main, fallback compositor)
- `jellyfin` + `jellyfin-openrc` + `jellyfin-tui` + `jellyfin-mpv-shim` (community — local server if ever wanted)
- `retroarch` + joypad autoconfig (community)
- `moonlight-qt` (community — if a gaming PC ever joins the LAN)
- **NOT packaged:** `steam` client (only `steam-devices`), `red` (the YouTube/Electron app — would need AppImage + glibc compat on musl), Kodi is packaged but ruled out by user

## Constraints to design around

1. **2 GB RAM** — one heavy app at a time; prefer mpv/web over multiple Electron apps; eMMC swap is a safety net, not a feature
2. **No AVX** — fine in practice (ffmpeg/chromium/mpv handle it) but relevant if picking builds or codecs
3. **32 GB eMMC** — OS + apps only; media lives on the LAN (Jellyfin), not locally; watch eMMC write life
4. **Any resolution, but render at ≤1080p** — Foyer lays out in dp units from 480p to 4K and gamescope uses the TV's preferred mode by default (Settings → Display lists every EDID mode). On this weak GPU the profile (`profiles/ideapad-120s.sh`) sets `RENDER_MAX=1920x1080`, so the UI/apps render at 1080p and gamescope upscales if the output is 4K. No HDR.
   **VAAPI driver:** the GPU is Gen9 (Apollo Lake) — the classic `i965` driver is required. The newer `iHD` (intel-media-driver) exposes HEVC VLD but decodes ~15× slower than real time on it (measured 2026-11-25: 20 s of 1080p30 HEVC took 52 s with iHD `vaapi-copy` vs 3 s with i965; ffmpeg software decode does it in ~5 s). `VA_DRIVER=i965` in the profile → `/etc/foyer/env.d/libva.conf`.
5. **musl/Alpine** — glibc-only binaries (AppImages, Steam) need extra work; prefer packaged software

## Session-stack gotchas (solved — do not regress)

- **seatd is mandatory** for gamescope/wlroots (no systemd-logind on Alpine); package `seatd`, openrc service, `/run/seatd.sock`
- **eudev is mandatory** — the box shipped with busybox mdev; libinput/wlroots can't enumerate input without `eudev` + `udev-trigger` (sysinit runlevel)
- **Xwayland is mandatory** — gamescope 3.16 spawns Xwayland even for wayland-native clients; without it gamescope **segfaults** (`segfault at 90`) with a confusing `Cannot find Xwayland binary` error first
- `hwdata` package fixes the `pnp.ids` warning; `drmModeAddFB2WithModifiers: Invalid argument` spam is a harmless fallback (no DRM modifiers on this iGPU)
- Red build: `-DCMAKE_SKIP_INSTALL_RPATH=ON` (cmake RPATH rewrite chokes on musl binaries), `-DRED_BUILD_TESTS=OFF`
- **gamescope ignores SIGTERM** — restart the session with `kill -9 <gamescope-wl pid>` (inittab respawns session.sh)
- **gamescope Wayland socket is `gamescope-0`** (in `$XDG_RUNTIME_DIR`), not `wayland-*`. Clients (including the v2 quick-menu overlay) use `WAYLAND_DISPLAY=gamescope-0`.
- **Quick-menu overlay works** via the `GAMESCOPE_EXTERNAL_OVERLAY=1` env var on the overlay client — gamescope composites it on top of the running app (strategy A from the plan).
- **No CEC**: the HD 500 iGPU does not expose a CEC adapter (no `/dev/cec*`, no `/sys/class/cec`). The `libcec` apk is for a Pulse-Eight USB adapter the box lacks. CEC is blocked until a USB CEC adapter is added.

## Verification

```sh
ssh htpc 'grep "model name" /proc/cpuinfo; free -h; cat /sys/class/dmi/id/product_name /sys/class/dmi/id/product_serial'
ssh htpc 'for c in /sys/class/drm/card1-*/; do echo "$c $(cat $c/status) $(cat $c/modes|head -1)"; done'
ssh htpc 'cat /sys/block/mmcblk0/size; swapon --show; df -h /; ip -brief a'
ssh htpc 'apk info -v | wc -l; rc-status'
ssh htpc 'cat /sys/class/hwmon/hwmon0/temp1_input'
```
