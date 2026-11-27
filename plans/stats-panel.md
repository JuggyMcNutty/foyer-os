# PLAN — Foyer system status panel: build-out (graphs, processes, telemetry, quick panel)

## Context

Settings → Stats (`StatsPage` in `foyer/src/screens/settings.cpp`) polls
`foyer-ctl sys stats` every 2 s and renders **text-only info rows**:
CPU % (total + per core), load, procs, uptime, RAM, swap, storage, GPU
busy/freq, temps, per-iface net rates. Flat — no history, no visualisation,
no per-process detail. The quick panel overlay has no system readout at all.

User wants all four extensions:

1. **History graphs** — rolling bar sparklines (CPU, RAM, network).
2. **Top processes** — top CPU consumers, killable.
3. **More telemetry** — disk I/O rates, GPU freq range, per-mount storage.
4. **Quick panel stats** — mini readout in the quick menu overlay.

Backend is `session/bin/foyer-ctl` (POSIX sh + awk, must stay busybox-awk
clean); parsing lives in `foyer/src/platform/sysctl.cpp` (unit-tested).

## Approach

### 1. Graph widget (new `ui::Graph` node)

- New node class in `foyer/src/ui/engine/widgets.{hpp,cpp}`: fixed 30-slot
  ring buffer of 0..1 values (2 s samples → 60 s window), `push(v)`, `clear()`.
- `paint()` override: dim rounded track (`t.surface_hi` at ~50% alpha) +
  vertical bars in `t.accent`, oldest → left, drawn with `Canvas::fill`
  (no polygon primitive exists; bars are the right primitive). Bars are
  `slot_w - gap` wide. Uses `c.push_alpha(alpha)` like `Box::paint`.
- `StatsPage` keeps three graphs and pushes a sample per poll:
  CPU (busy/100), RAM (used/total), network (total rx+tx, adaptive scale:
  max of window with a 1 MB/s floor, current rate shown in text).
- Layout: full-width graph node (~44 dp) directly under its section's first row.

### 2. Top processes

- **`foyer-ctl sys procs [N]`** (N default 10): same double-sample pattern as
  `sys stats` (awk `system("sleep 0.5")` between samples). For each
  `/proc/<pid>`: utime+stime from `/proc/<pid>/stat` (parse after the last
  `)` — comm may contain spaces), rss pages from `/proc/<pid>/statm`.
  CPU% = `100 × Δticks × nproc / Δtotal_ticks` (top-style, % of one core),
  total from the aggregate `cpu` line. Output
  `proc\tPID\tCPU%\tMEM_KB\tNAME`, insertion-sorted by CPU desc (POSIX awk,
  no asort), top N.
- **`foyer-ctl sys kill PID`**: `kill -TERM`.
- **Parsing**: `ProcStat { pid, cpu_pct, mem_kb, name }` +
  `parse_sys_procs()` in sysctl.{hpp,cpp}; unit tests.
- **UI**: "Processes" section in StatsPage, one `kit::RowButton` per entry —
  label `name (pid)`, value `12% · 340 MB`. Accept → `ConfirmDialog`
  (same pattern as PowerPage) → `sys kill <pid>` job → toast.
- StatsPage tick queues `sys stats` + `sys procs` together (job queue is
  serial; each ~0.5 s — fits the 2 s cycle).

### 3. More telemetry (extend `sys stats`)

- **Disk I/O**: root disk's major:minor from `/proc/self/mountinfo`
  (field 3 of the mount-point-`/` line) matched in `/proc/diskstats`;
  sector deltas over the 0.5 s window → `dio\tREAD_KB/s\tWRITE_KB/s`.
- **GPU freq range**: extend the gpu line to
  `gpu\tbusy\tfreq\tmin\tmax` — i915 `gt_min_freq_mhz`/`gt_max_freq_mhz`,
  amdgpu from `pp_dpm_sclk` min/max lines. Parser keeps accepting the old
  3-field form (min/max = 0 = n/a).
- **Per-mount storage**: `disk\tMOUNT\tused\ttotal` for every real mount
  (skip tmpfs/devtmpfs/proc/squashfs/overlay), instead of just `/`.
  `StatsSnapshot`: `disk_used_kb/disk_total_kb` → `std::vector<MountStat>`;
  add `disk_read_kbs/disk_write_kbs`, `gpu_freq_min/gpu_freq_max`.
- **UI**: Storage section shows one row per mount; new "Disk I/O" row
  (`4.2 MB/s down · 0.1 MB/s up`); GPU row shows `busy% · freq (min–max) MHz`.

### 4. Quick panel stats

- Dim one-liner under the QuickPanel header:
  `CPU 12% · RAM 3.2/8.0 GB · 45°C · 4.5 MB/s` (net = total rx+tx).
- Poll `sys stats` every 2 s in `QuickPanel::tick()` while the layer is on
  top (`e.top() == this`, same guard as StatsPage). Works in both modes —
  the external overlay is a separate Foyer process with its own job queue
  (it already runs `audio volume/get`).
- Add `bool tick(Engine&, float) override` to QuickPanel + `stats_line_`
  text node + `poll_` member.

## Files to modify

| File | Change |
|---|---|
| `foyer/src/ui/engine/widgets.{hpp,cpp}` | new `Graph` node (ring buffer + bar paint) |
| `foyer/src/screens/settings.{hpp,cpp}` | StatsPage: graphs, processes section, mounts, disk I/O, GPU range |
| `foyer/src/screens/quick_panel.{hpp,cpp}` | stats line + 2 s poll |
| `foyer/src/platform/sysctl.{hpp,cpp}` | `ProcStat`/`parse_sys_procs`, `MountStat`, new snapshot fields |
| `session/bin/foyer-ctl` | `sys procs`, `sys kill`, extended `sys stats` (dio, gpu min/max, mounts) |
| `foyer/tests/test_core.cpp` | parsing tests (procs, dio, gpu 5-field, mounts, old gpu form) |
| `foyer/tests/test_engine.cpp` | Graph push/trim + paint smoke test |
| `aports/foyer/APKBUILD` | pkgrel bump (5 → 6) |

## Reuse (existing code to build on)

- `kit::info_row`, `kit::section`, `kit::RowButton`, `kit::list`
  (`foyer/src/screens/kit.{hpp,cpp}`) — all StatsPage rows.
- `Page` base + `StatsPage::tick` polling pattern (`e.top()` guard,
  `app_.jobs().busy()` check) — copy for QuickPanel.
- `ConfirmDialog` usage pattern from PowerPage
  (`settings.cpp` ~line 635) for process kill.
- `foyer-ctl sys stats` awk double-sample skeleton (`session/bin/foyer-ctl`
  ~line 807) for `sys procs`.
- `with_alpha` (`tokens.hpp:51`), `Canvas::fill/rounded/push_alpha`.
- `fmt_kb`/`fmt_bps` (`sysctl.cpp`) for new rows.
- `App::execute(":stats")` / `--open :stats` for screenshot verification.

## Steps

- [x] 1. `ui::Graph` node in widgets.{hpp,cpp}: ring buffer, bar paint, test
      in test_engine.cpp.
- [x] 2. `foyer-ctl`: `sys procs [N]` + `sys kill PID` (busybox-awk clean);
      verify output by hand on the box.
- [x] 3. `foyer-ctl sys stats`: add `dio`, gpu min/max, per-mount `disk`
      lines; keep old lines intact.
- [x] 4. sysctl.{hpp,cpp}: `parse_sys_procs`, `MountStat`, new snapshot
      fields + unit tests (incl. old 3-field gpu form).
- [x] 5. StatsPage: CPU/RAM/net graphs (push on poll), Processes section
      with kill confirm, per-mount storage, Disk I/O row, GPU range.
- [x] 6. QuickPanel: stats line + tick poll (internal + overlay modes).
- [x] 7. Bump foyer pkgrel, rebuild APKs (`scripts/build-apks.sh foyer`),
      provision the box, live TV check (stats page + quick panel over an
      app), kill a test process (e.g. a `sleep` spawned on the box).

## Verification

- `cd foyer && cmake -S . -B build && cmake --build build && ./build/tests/foyer_tests`
  (new suites: Graph, parse_sys_procs, extended sys stats).
- Screenshot: put a symlink to `session/bin/foyer-ctl` on PATH, then
  `FOYER_DATA_DIR=$PWD/data ./build/src/foyer -c /tmp/cfg --size 3840x2160 --open :stats --screenshot stats.png`
  — graphs render empty-to-filled, processes section populated, new rows
  present. Repeat at 1280x720 for small-screen layout.
- On the box: `foyer-ctl sys procs 5`, `foyer-ctl sys stats` (check
  `dio`/`gpu`/`disk` lines), then the UI: stats page live polling, process
  kill (spawn `sleep 1000` on the box, kill it from the panel), quick panel
  stats line while an app is running (overlay mode).
