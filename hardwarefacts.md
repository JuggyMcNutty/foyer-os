# HTPC Mini PC — Hardware Facts

> Source of truth for the box at `192.168.1.123` (ssh alias: `htpc`, DNS: `streamyboi`).
> Verified via SSH on 2026-11-26 (fresh foyer-os image install, first boot).
> Re-verify with the commands in the [Verification](#verification) section before trusting stale values.
>
> The previous box (ideapad 120S, N3350) is documented in
> [hardwarefacts-ideapad-120s.md](hardwarefacts-ideapad-120s.md).

## TL;DR

Repurposed **GEOMARK Geobook 240** 14" 2-in-1 laptop motherboard in a mini-PC enclosure — no battery, no internal screen, AC-powered, headless via HDMI.

- **CPU:** Intel Pentium Silver N5030 — 4 cores / 4 threads, 1.10→3.16 GHz, SSE4.2 only (**no AVX**)
- **RAM:** 8 GB DDR4 (7.5 GiB visible)
- **Storage:** 128 GB SATA disk (**111.8 GiB usable**) in a **PNY USB3.0-to-SATA dock** — the disk is external USB, not internal
- **GPU:** Intel UHD Graphics 605 (i915, Gemini Lake Gen 9.5) — **HDMI out on the motherboard**, currently a **dummy plug** (emulates an AOC 28E850 HDR, 4K60). HDMI on Gemini Lake is **1.4**: 4K60 only in 4:2:0, 4:4:4 tops out at 4K30, **no HDR**
- **Audio:** HDA controller with **HDMI/DP codec only** (no analog) — digital stereo to the TV
- **Network:** Realtek RTL8153 USB Gigabit Ethernet in the dock — **can fail to come up at boot; a reboot fixes it**
- **Boot:** UEFI, systemd-boot, Alpine `linux-lts` 6.18.65

## Identity / DMI

| Field | Value |
|---|---|
| Product | GeoBook 240 |
| Board | `EM_IG218_200B_ENE_TI_V2.0` |
| Serial | `1036999892994` |

## CPU

- **Intel(R) Pentium(R) Silver N5030** — Gemini Lake, 14 nm, 6 W TDP
- 4 cores / 4 threads (no hyperthreading), 1.10 GHz base, burst ~3.16 GHz
- SIMD ceiling: **SSE4.2**. No AVX / AVX2 / FMA — same class as the N3350
- Passively cooled (laptop-board heatsink); ~36–41 °C at idle (coretemp TCPU)

## RAM

- **8 GB DDR4** (~7.5 GiB visible)
- 2 GB swapfile (`/swapfile`, created on first boot from the profile's `SWAP_MB`)
- Plenty of headroom for Foyer + one heavy app; can stack a browser-class app

## Graphics

- **Intel UHD Graphics 605** (PCI `0000:00:02.0`, device `8086:3184`)
- i915 identifies it as **geminilake** (display version 10.00, Gen 9.5), DMC firmware v1.4
- `drm: Unknown revision 0x06` at boot is a harmless GLK message
- Connectors: **HDMI-A-1** (in use), HDMI-A-2 (untested), DP-1 (eDP panel port — no panel)
- **HDMI link is 1.4** (Gemini Lake SoC): 4K60 requires 4:2:0, 4:4:4 is 4K30 max, no HDR
  metadata.
- **Current panel: TOSHIBA TV, 52" (EDID TSB/48, "TOSHIBA-TV", made 2022-w20)** — the
  user calls it "the 4K monitor". Verified with edid-decode 2026-11-26: preferred
  1920x1080@60, **native 3840x2160@30** (HDMI VIC 1, 297 MHz TMDS), 4K also at 25/24 Hz
  and 4096x2160@24; the TV lists 4K50/60 but only in a **YCbCr 4:2:0** block at 594 MHz
  TMDS — unachievable (VSDB max TMDS = 300 MHz, i.e. HDMI 1.4). Deep colour 36/30-bit +
  RGB 4:4:4, audio LPCM 2ch / DD 5.1 / DD+ / TrueHD, no HDR metadata, no VRR. The session
  runs native 4K@30 (`WIDTH=native`). The old dummy plug (AOC28E850.HDR, 4K60 native)
  was used during bring-up only.
- Vulkan via ANV (`mesa-vulkan-intel`) — gamescope composites fine at 4K
- **VAAPI: must use the `i965` driver** (profile `VA_DRIVER=i965` →
  `/etc/foyer/env.d/libva.conf`, written by make-image.sh / provision.sh). The `iHD`
  (intel-media-driver 26.2.1) is **broken on Gemini Lake just like on Apollo Lake**:
  4K HEVC 10-bit (5 s clip) decodes in **190 s with iHD vs 3.8 s with i965**
  (~1.3× realtime; software manages ~1.5×). Measured 2026-11-26 with
  `mpv --vo=null --untimed --hwdec=vaapi-copy`.

## Audio

- PCI `0000:00:0e.0` — Intel HDA controller (`8086:3198`)
- **HDMI/DP codec only** (pcm 3/7/8) — no analog codec on this board; audio goes to the TV
- **Audio gotcha (solved):** the kernel's SOF driver (`sof-audio-pci-intel-apl`) claims
  the controller and, without the `sof-firmware` package, creates **no soundcards at all**.
  The image forces the legacy HDA driver: `/etc/modprobe.d/foyer-audio.conf` with
  `options snd-intel-dspcfg dsp_driver=1` (note: `0` = auto, which picks SOF).
- PipeWire sink: `Built-in Audio Digital Stereo (HDMI)`, routed by `foyer-ctl audio output/restore`

## Storage

| Device | What | Layout / size | Notes |
|---|---|---|---|
| `/dev/sda` | 128 GB SATA disk in a **PNY USB3.0-to-SATA dock** (154b:8001), USB bus 2 | p1: 256 MB FAT `/boot` (FOYER-ESP) · p2: 111.5 GB ext4 `/` | Grows to the disk on first boot (foyer-firstboot) |
| (none) | — | — | the board's native SATA (00:12.0) has no drive; SD slot (00:1f.1) has no card |

## I/O & USB layout

- **HDMI:** motherboard port → TV (dummy plug during bring-up). Board exposes HDMI-A-1 + HDMI-A-2 in sysfs
- **Power:** mains directly (no battery)
- **USB bus 2 (xHCI 3.0):** PNY SATA dock (disk) + Realtek RTL8153 USB Ethernet (`eth0`)
- **USB bus 1 (xHCI 2.0):** Realtek Bluetooth radio (`0bda:c821`) — **broken dongle, stuck in a USB reset loop** (`hci0: command 0xfc61 tx timeout`); unplug it; **XING WEI 2.4G air mouse** (`4842:0001`)
- No Wi-Fi/BT on the board itself (BT only via the dongle)

## Input — XING WEI 2.4G air mouse (`4842:0001`)

USB composite device. The event nodes re-number on every re-plug; as of 2026-11-27 it
exposes **5** nodes (event4 kbd, event5 Mouse, event6 Consumer Control, event7 System
Control, event8) and **four** of them advertise MSC_SCAN — the same button code can be
mirrored onto several nodes at once, so a reader must dedup by code + time window
(`Airmouse::step()`, 100 ms). 15 physical buttons: d-pad (left/right/up/down), enter,
menu 1/2/3, power, mute, del, click, return, vol down, vol up — plus left/right click
and wheel. **None of the buttons are
EV_KEY/BTN_*** — the firmware reports every button as **EV_MSC MSC_SCAN** with a 24-bit
HID usage (`page<<16 | usage<<8`) and emits the code **twice per press** (press report,
release report). The compositor never sees MSC_SCAN, so Foyer reads it itself
(`foyer/src/input/airmouse.cpp`, match string `XING WEI`) and remaps it in
Settings → Air mouse. Pointer motion is ordinary REL_X/REL_Y (wave) and **streams
continuously at ~60 Hz with ±1 jitter even at rest** — the engine's hover logic rebases
after D-pad focus changes and ignores moves under 6 px so the stream can't steal focus.

Observed MSC codes (XING WEI unit, captured 2026-11-26):

| MSC (hex) | HID meaning | Button (user-confirmed order) |
|---|---|---|
| `0x090001` | Button 1 | left click (physical) |
| `0x010081` | Desktop Y | wheel (same code up & down) |
| `0x070065` | System Power | power |
| `0x07002A` | keyboard 0x2A (del) | click |
| `0x0C00CF` | consumer 0xCF | del |
| `0x0C0223` | consumer 0x223 | mute |
| `0x0C0224` | consumer 0x224 | return |
| `0x0C00EA` / `0x0C00E9` | consumer | vol down / vol up |
| `0x0C0044` / `0x0C0045` / `0x0C0042` / `0x0C0043` | consumer | enter / menu 1 / menu 2 / menu 3 |

The device also floods **EV_KEY code 0 (KEY_RESERVED) release** events on every HID
report — ignore them. Right-click was never observed (possibly one of the consumer
codes above; the remap page's live highlight identifies any button).

## Network

- `eth0` = Realtek RTL8153 over USB, DHCP on 192.168.1.0/24 → currently `192.168.1.123`
- Managed by ifupdown-ng; `foyer-net.start` DHCP-configures every wired NIC and retries
  for 60 s (USB NICs can enumerate late)
- **Gotcha:** the r8153 sometimes does not come up at boot (no IP, "No route to host");
  a reboot brings it back. The 60 s retry in foyer-net.start covers the late-enumeration
  case; a fully dead adapter still needs a reboot.

## Kernel & boot

- `linux-lts` **6.18.65-0-lts** (Alpine 3.24), UEFI boot via systemd-boot on FOYER-ESP
- Boot args: `root=LABEL=foyer-root rootfstype=ext4 modules=ext4 quiet loglevel=3 console=tty0`
- **RTC is not set** (no working battery?): first boot shows Jan 1 2012 until chrony steps
  the clock (~15 years off). Harmless after the first sync.
- UEFI boots the USB-docked disk fine (no Secure Boot issue seen)

## Constraints to design around

1. **HDMI 1.4 is the ceiling** — 4K60 only in 4:2:0, no 4:4:4 above 30 Hz, no HDR. The
   decode side is strong (4K HEVC 10-bit at 1.3× realtime with i965); the link is not.
   If 4K60 4:4:4 + HDR is the goal, this SoC family can't deliver it over HDMI.
2. **No AVX** — fine in practice (ffmpeg/mpv/chromium handle it)
3. **Disk is external USB** — the dock is single-point-of-failure; the board's internal
   SATA/SD are empty if an internal disk is ever wanted
4. **Render at native** (profile `RENDER_MAX=native`): 8 GB RAM + UHD 605 handle 4K UI
   rendering; gamescope outputs 4K60
5. **musl/Alpine** — glibc-only binaries (AppImages, Steam) need extra work

## Session-stack gotchas (geobook-specific)

- **SOF vs HDA audio:** `options snd-intel-dspcfg dsp_driver=1` in
  `/etc/modprobe.d/foyer-audio.conf` (shipped in the image). Without it the SOF driver
  claims the HDA controller and no soundcards appear.
- **VAAPI driver:** i965, not iHD (see Graphics). `/etc/foyer/env.d/libva.conf`
  (`export LIBVA_DRIVER_NAME=i965`).
- **USB Ethernet flake:** reboot to recover (see Network).
- **BT dongle:** unplug the broken Realtek c821 dongle (USB reset loop spam).

## Verification

```sh
ssh htpc 'grep "model name" /proc/cpuinfo; nproc; free -h; cat /sys/class/dmi/id/product_name'
ssh htpc 'for c in /sys/class/drm/card1-*/; do echo "$c $(cat $c/status)"; done; foyer-ctl display native'
ssh htpc 'lsblk; swapon; cat /proc/swaps'
ssh htpc 'cat /proc/asound/cards; XDG_RUNTIME_DIR=/run/foyer wpctl status | grep -A3 Sinks'
ssh htpc 'cat /sys/class/thermal/thermal_zone*/temp'
```
