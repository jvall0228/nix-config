---
title: "feat: Add animated wallpaper system with rofi switcher"
type: feat
status: completed
date: 2026-03-02
deepened: 2026-03-02
origin: docs/brainstorms/2026-03-02-animated-wallpapers-brainstorm.md
---

# feat: Add animated wallpaper system with rofi switcher

## Enhancement Summary

**Deepened on:** 2026-03-02
**Sections enhanced:** 7
**Research agents used:** mpvpaper+Nvidia, swww/awww transitions, rofi scripting, battery detection

### Key Improvements

1. **CRITICAL: mpvpaper `vo=gpu-next` does NOT work** — mpvpaper forces `vo=libmpv`. The original plan's flags were wrong. Corrected to use `hwdec=auto gpu-api=vulkan`.
2. **CRITICAL: mpvpaper has an unfixed memory leak on loop** — needs periodic restart (every 30 min) as a workaround.
3. **Daemon readiness: poll `swww query` instead of `sleep 1`** — eliminates race condition on Video-to-swww transitions.
4. **Rofi script mode instead of chained dmenu** — enables seamless two-level navigation with back button and thumbnail previews.
5. **Battery detection: enumerate by `type=Mains`** — don't hardcode `/sys/class/power_supply/AC/online`, poll every 5 seconds (negligible cost).
6. **4K GIF memory warning** — a 100-frame 4K GIF uses ~3.3 GB RAM. Recommend resizing animated wallpapers.
7. **dGPU wake on mpvpaper** — hardware decoding wakes discrete GPU via cuda probing. Accept the power draw or use `hwdec=no`.

### New Risks Discovered

- **mpvpaper memory leak** ([#101](https://github.com/GhostNaN/mpvpaper/issues/101)) — unfixed, Nvidia+OpenGL root cause. Mitigated with periodic restart wrapper.
- **dGPU wake** ([mpv#13668](https://github.com/mpv-player/mpv/issues/13668)) — mpv's cuda probe wakes the Nvidia dGPU even when rendering on iGPU. No clean workaround.

---

## Overview

Add a multi-mode wallpaper system to the Hyprland setup supporting static images, animated GIFs/APNGs, video wallpapers, and slideshows — switchable via a rofi menu. Includes battery-aware auto-switching to static mode.

(see brainstorm: `docs/brainstorms/2026-03-02-animated-wallpapers-brainstorm.md`)

## Problem Statement / Motivation

The current setup uses a single hardcoded static PNG wallpaper via swww. The user wants maximum visual impact with animated/video wallpapers, a slideshow rotation, and a discoverable UI for switching between them.

## Proposed Solution

A bash-driven wallpaper manager with four modes, managed via PID files and a state file. swww handles static/GIF/APNG/slideshow modes; mpvpaper handles video mode. A rofi script-mode menu provides the switching UI. A lightweight polling loop handles battery-aware auto-switching.

### State Machine

```
         ┌──────────┐
    ┌───>│  Static   │<───┐
    │    └─────┬────┘     │
    │          │          │ (battery auto-switch)
    │    ┌─────▼────┐     │
    ├───>│ GIF/APNG  │────┤
    │    └─────┬────┘     │
    │          │          │
    │    ┌─────▼────┐     │
    ├───>│ Slideshow │────┤
    │    └─────┬────┘     │
    │          │          │
    │    ┌─────▼────┐     │
    └───>│  Video    │────┘
         └──────────┘

All transitions go through a single `wallpaper-set` script.
swww-daemon runs in: Static, GIF/APNG, Slideshow
mpvpaper runs in: Video (swww-daemon killed)
```

### Mode Transition Commands

| From | To | Actions |
|------|----|---------|
| Static/GIF/Slideshow | Static/GIF/APNG | Kill slideshow (if running). `swww img <file>` |
| Static/GIF/Slideshow | Slideshow | Kill slideshow (if running). Launch slideshow script |
| Static/GIF/Slideshow | Video | Kill slideshow (if running). Kill swww-daemon. Launch mpvpaper |
| Video | Static/GIF/APNG | Kill mpvpaper. Start swww-daemon. **Poll `swww query`** until ready. `swww img <file>` |
| Video | Slideshow | Kill mpvpaper. Start swww-daemon. **Poll `swww query`** until ready. Launch slideshow script |

## Technical Considerations

### Process Management — PID files

Each background process writes a PID file to `~/.local/state/wallpaper/`:

- `swww-daemon.pid` — swww daemon PID
- `slideshow.pid` — slideshow loop PID
- `mpvpaper.pid` — mpvpaper PID
- `mpvpaper-restarter.pid` — mpvpaper restart wrapper PID (see memory leak mitigation)
- `battery-monitor.pid` — battery polling loop PID
- `mode` — current mode string (`static`, `gif`, `slideshow`, `video`)
- `current-file` — path of the current wallpaper/video file
- `last-animated-mode` — last non-static mode + file (for battery restore)
- `battery-override` — if present, battery auto-switch is suppressed

A `wallpaper-cleanup` function kills any tracked PIDs before launching a new mode. PID files are checked with `kill -0` before trusting them.

Why PID files over systemd services: simpler, keeps everything in a single bash script, avoids `Conflicts=`/`BindsTo=` complexity. The wallpaper manager is a user convenience tool, not a critical service — if it crashes, the screen still works, just with no wallpaper.

### Battery Detection — Polling loop

#### Research Insights

**Enumerate by type, not by name.** The power supply name varies by hardware (`AC`, `ACAD`, `ADP0`, etc.). The reliable, portable approach:

```bash
get_ac_online() {
  for ps in /sys/class/power_supply/*/; do
    if [ "$(cat "$ps/type" 2>/dev/null)" = "Mains" ]; then
      cat "$ps/online" 2>/dev/null
      return
    fi
  done
  echo "-1"  # no mains adapter found
}
```

**`inotifywait` does NOT work on sysfs** — it's a virtual filesystem that doesn't emit inotify events. `systemd.path` units have the same limitation. Polling is the only home-manager-only approach.

**5-second poll interval** (changed from 60s). Reading a single sysfs file is a direct kernel memory read with zero disk I/O. 12 reads/minute is immeasurably small. The faster interval gives near-instant response to plug/unplug events.

**No system-level changes needed.** udev rules and acpid handlers would require `modules/nixos/` changes. The sysfs poll keeps everything in `home/linux/`.

#### Implementation

```
Battery monitor (5-second poll loop):
  Previous state = unknown

  Every 5 seconds:
    State = get_ac_online()
    If state changed from previous:
      If state == 0 (battery):
        If battery-override file does NOT exist:
          Save current mode + file to last-animated-mode
          Switch to static fallback
      If state == 1 (AC):
        Clear battery-override flag
        If last-animated-mode exists, restore it
    Previous state = state
```

Manual override: When the user selects a non-static mode via rofi while on battery, the script writes a `battery-override` file. This prevents the polling loop from reverting. The flag is cleared when AC power is reconnected.

### Nvidia Considerations

#### Research Insights — CRITICAL CORRECTIONS

**mpvpaper forces `vo=libmpv`.** You CANNOT use `vo=gpu-next` or `vo=gpu`. The maintainer confirmed: "mpvpaper does not support any other vo than 'libmpv'." ([#65](https://github.com/GhostNaN/mpvpaper/issues/65))

**`hwdec=auto` resolves to `nvdec-copy` on Nvidia**, which is the correct decoder. The `-copy` variant copies decoded frames back to system RAM, avoiding GPU-to-GPU transfer issues with mpvpaper's OpenGL render path. The `libva init failed` error for `nvidia_drv_video.so` is harmless — mpv falls back automatically.

**`gpu-api=vulkan` mitigates the memory leak.** See the memory leak section below.

**Do NOT set `__NV_PRIME_RENDER_OFFLOAD=1` for mpvpaper.** If Hyprland runs on the iGPU (standard Optimus setup), mpvpaper will also use the iGPU. Forcing dGPU is counterproductive for a background wallpaper.

**However: hardware decoding wakes the dGPU regardless.** mpv's cuda hwdec driver calls `cuInit()` during initialization, which wakes the Nvidia discrete GPU even when rendering on the iGPU ([mpv#13668](https://github.com/mpv-player/mpv/issues/13668)). No clean workaround exists. Options:
- Accept the power draw (dGPU awake while video wallpaper is active)
- Use `hwdec=no` for software decoding (higher CPU, dGPU stays asleep)
- Only use video wallpapers on AC power (battery auto-switch handles this)

#### Corrected mpvpaper Command

```bash
mpvpaper -s -o "no-audio loop hwdec=auto gpu-api=vulkan" "$MONITOR" "$VIDEO_FILE"
```

- `-s` (auto-stop) — suspends mpvpaper into a holder process when fully occluded, freeing RAM and CPU. Better than `-p` (auto-pause) which only pauses playback.
- `no-audio` — no audio track for wallpaper
- `loop` — loop the video
- `hwdec=auto` — resolves to `nvdec-copy` on Nvidia
- `gpu-api=vulkan` — mitigates the Nvidia+OpenGL memory leak
- `$MONITOR` — resolved dynamically via `hyprctl monitors -j | jq -r '.[0].name'`

### mpvpaper Memory Leak — CRITICAL

**There is an unfixed memory leak in mpvpaper when looping videos** ([#101](https://github.com/GhostNaN/mpvpaper/issues/101), open as of December 2025). Memory grows by MBs per loop cycle. After 24 hours, a 300MB video process can grow to 2GB+. After 3 days, one user reported 45GB consumed.

**Root cause:** Nvidia+OpenGL bug in mpv itself ([mpv#15099](https://github.com/mpv-player/mpv/issues/15099)).

**Mitigation: periodic restart wrapper.** The `wallpaper-set video` command wraps mpvpaper in a restart loop:

```bash
# mpvpaper-restarter concept
while true; do
    mpvpaper -s -o "no-audio loop hwdec=auto gpu-api=vulkan" "$MONITOR" "$VIDEO_FILE" &
    MPVPAPER_PID=$!
    echo "$MPVPAPER_PID" > "$STATE_DIR/mpvpaper.pid"
    sleep 1800  # restart every 30 minutes
    kill "$MPVPAPER_PID" 2>/dev/null
    wait "$MPVPAPER_PID" 2>/dev/null
    sleep 1
done
```

The restarter PID is tracked separately in `mpvpaper-restarter.pid` so `wallpaper-cleanup` kills both.

### Asset Location — Outside the repo

Wallpaper assets live in `~/Pictures/Wallpapers/` and `~/Videos/Wallpapers/` (not in the git repo). This avoids bloating the repo with binary files and prevents the auto-upgrade at 04:00 from wiping user-added wallpapers.

The fallback static wallpaper remains `~/nix-config/assets/wallpaper.png` (the Stylix color seed).

#### GIF/APNG Memory Warning

swww decodes ALL GIF frames into shared memory. At 4K (3840x2160) with 4 bytes per pixel:

- **Per frame:** ~33 MB
- **50 frames:** ~1.66 GB
- **100 frames:** ~3.32 GB

**Recommendation:** Resize animated GIFs to monitor resolution before use. Keep under 30-50 frames. Use `gifsicle` to resize/optimize. Static PNGs have no such overhead.

### Rofi Menu — Script mode with thumbnails

#### Research Insights

**Use rofi script mode instead of chained dmenu.** Script mode keeps a single rofi window open across menu levels, supports back navigation, and allows thumbnail previews via `ROFI_INFO` and `ROFI_DATA` for state.

**Key rofi-script protocol:**
- `ROFI_RETV=0` — initial call, show root menu
- `ROFI_RETV=1` — user selected an entry
- `ROFI_INFO` — hidden metadata on the selected row (use for file paths)
- `ROFI_DATA` — persistent state between invocations (use for menu level)
- Escape closes rofi automatically, no cleanup needed
- `thumbnail://` prefix on `icon` property enables wallpaper previews

#### Menu Design

```
Level 1 (ROFI_DATA=root):
  prompt: "Wallpaper"
  entries:
    "Static"        icon=image-x-generic     info=mode:static
    "GIF/APNG"      icon=image-gif           info=mode:gif
    "Slideshow"     icon=media-playlist       info=mode:slideshow
    "Video"         icon=video-x-generic     info=mode:video

Level 2 (ROFI_DATA=mode:static|gif|video):
  prompt: "Static" (or GIF, Video)
  entries:
    ".. Back"       icon=go-previous          info=__back__
    "sunset.jpg"    icon=thumbnail:///path    info=/full/path/to/file
    "tokyo.gif"     icon=thumbnail:///path    info=/full/path/to/file

On file selection:
  Call wallpaper-set <mode> <file> and exit

On "Slideshow" selection (no sublevel):
  Call wallpaper-set slideshow and exit
```

**File discovery:** `find ~/Pictures/Wallpapers/ -type f \( -name '*.jpg' -o -name '*.png' -o -name '*.gif' -o -name '*.apng' -o -name '*.webp' \)` at runtime.

**Empty directory:** Show `"(no files found)"` with `nonselectable=true`.

**Invocation:**

```bash
rofi -show wallpaper -modi "wallpaper:wallpaper-menu" -show-icons \
  -theme-str 'listview { columns: 3; lines: 3; }' \
  -theme-str 'element-icon { size: 150px; }'
```

### swww Transition Details

#### Research Insights

**14 transition types available:** `none`, `simple`, `fade`, `left`, `right`, `top`, `bottom`, `wipe`, `wave`, `grow`, `center`, `outer`, `any`, `random`

**Key parameters:**

| Flag | Default | Notes |
|------|---------|-------|
| `--transition-type` | `simple` | Use `fade` for smooth crossfade, `random` for variety |
| `--transition-duration` | `3` | Seconds. Does NOT work with `simple` type. |
| `--transition-fps` | `30` | Use `60` for smooth transitions |
| `--transition-step` | `90` | RGB change per frame (only for `simple`) |
| `--transition-bezier` | `.54,0,.34,.99` | Easing curve |
| `--transition-angle` | `45` | For `wipe` and `wave` |
| `--transition-pos` | `center` | For `grow`/`outer`. Accepts `center`, `top-left`, pixels, percentages |

**Environment variable overrides:** `SWWW_TRANSITION`, `SWWW_TRANSITION_FPS`, `SWWW_TRANSITION_DURATION`, etc. Use these in the slideshow script to avoid repeating flags.

**Daemon readiness — poll `swww query` instead of `sleep 1`:**

```bash
swww-daemon &
while ! swww query 2>/dev/null; do
    sleep 0.1
done
swww img /path/to/wallpaper.png
```

This succeeds as soon as the daemon is actually ready, regardless of system speed. Use this for both initial startup and Video-to-swww transitions.

**`swww restore`** re-applies the last displayed image. Useful for persist-across-reboot behavior.

**swww -> awww rename:** Binary names changed to `awww`/`awww-daemon`. Nixpkgs PR #478051 adds `awww` with a `swww` alias. For now, `pkgs.swww` still works. The plan should use `swww` in code but note the upcoming rename.

### Stylix Conflict Resolution

`stylix.image` in `modules/nixos/stylix.nix` is the color-scheme seed only. swww overrides the runtime wallpaper. No Stylix target changes needed — Stylix does not inject a wallpaper-setting command into Hyprland's exec-once; it only passes the image to targets that request it (greetd, hyprlock).

### Hyprlock — Intentionally static

`hyprlock.nix` keeps its hardcoded `path = "~/nix-config/assets/wallpaper.png"`. The lock screen should always be static — animated lock screens waste GPU during what should be idle. This is a feature, not a bug.

### Suspend/Resume

mpvpaper's `-s` (auto-stop) frees resources when the wallpaper is occluded. On suspend/resume, mpvpaper may not recover correctly. Add to `hypridle`'s `after_sleep_cmd`:

```
after_sleep_cmd = "hyprctl dispatch dpms on && ~/.local/bin/wallpaper-restore"
```

`wallpaper-restore` reads the state file and re-applies the current mode. For video mode, this kills and restarts the mpvpaper-restarter.

### Slideshow Defaults

- Interval: 5 minutes
- Source: all images in `~/Pictures/Wallpapers/` (shuffled with `sort -R`)

**Slideshow script pattern (from swww community):**

```bash
export SWWW_TRANSITION_FPS=60
export SWWW_TRANSITION_STEP=2

while true; do
    find "$WALLPAPER_DIR" -type f \( -name '*.jpg' -o -name '*.png' -o -name '*.webp' \) |
    sort -R |
    while read -r img; do
        swww img "$img" --transition-type random --transition-duration 2
        sleep 300
    done
done
```

## Acceptance Criteria

- [x] `wallpaper-set static <file>` sets a static wallpaper via swww
- [x] `wallpaper-set gif <file>` sets an animated GIF/APNG via swww
- [x] `wallpaper-set video <file>` plays a video wallpaper via mpvpaper (with restart wrapper)
- [x] `wallpaper-set slideshow` starts cycling wallpapers from `~/Pictures/Wallpapers/`
- [x] Rofi menu (`$mod, W`) opens a script-mode wallpaper picker with thumbnails
- [x] Switching from Video to any swww mode restarts swww-daemon cleanly (poll-based, no blind sleep)
- [x] On AC disconnect, wallpaper auto-switches to static (within 5 seconds)
- [x] On AC reconnect, previous animated mode is restored
- [x] Manual override via rofi while on battery is respected until AC reconnect
- [x] System survives suspend/resume with wallpaper restored
- [x] Empty wallpaper directories show a user-friendly message, not a crash
- [x] `nixos-rebuild switch` does not break a running wallpaper session
- [x] mpvpaper restarts every 30 minutes to mitigate memory leak

## Implementation Phases

### Phase 1: Core wallpaper manager script

Create `home/linux/wallpaper.nix` with:

- `wallpaper-set` script (mode switching, PID management, state file, swww query polling)
- `wallpaper-menu` script (rofi script-mode integration with thumbnails)
- `wallpaper-init` script (startup: create dirs, start swww-daemon with query poll, apply last wallpaper or default)
- Package declarations: `mpvpaper`, `jq` added to `home.packages`
- Move `swww` package declaration from `hyprland.nix` to `wallpaper.nix`

Files:
- **Create** `home/linux/wallpaper.nix` — new module
- **Modify** `home/linux/default.nix:8` — add `./wallpaper.nix` to imports
- **Modify** `home/linux/hyprland.nix:14` — remove `swww` from packages (moved to wallpaper.nix)
- **Modify** `home/linux/hyprland.nix:34-35` — replace hardcoded swww exec-once with `wallpaper-init`
- **Modify** `home/linux/hyprland.nix` — add `"$mod, W, exec, sh -c 'rofi -show wallpaper -modi \"wallpaper:wallpaper-menu\" -show-icons'"` keybind

### Phase 2: Battery-aware auto-switching

Add to `wallpaper.nix`:

- `wallpaper-battery-monitor` script (5-second poll loop with portable Mains detection)
- Launch in Hyprland exec-once
- Override flag logic

Files:
- **Modify** `home/linux/wallpaper.nix` — add battery monitor script
- **Modify** `home/linux/hyprland.nix` — add battery monitor to exec-once

### Phase 3: Suspend/resume resilience + mpvpaper restart wrapper

- `wallpaper-restore` script that reads state file and re-applies current mode
- mpvpaper restart wrapper (30-minute cycle to mitigate memory leak)
- Hook into hypridle's `after_sleep_cmd`

Files:
- **Modify** `home/linux/wallpaper.nix` — add restore script and restart wrapper
- **Modify** `home/linux/hyprlock.nix` — update `after_sleep_cmd`

## Dependencies & Risks

**Dependencies:**
- `pkgs.mpvpaper` — available in nixpkgs (version 1.8, Nvidia fix in 1.6+)
- `pkgs.swww` — already in use, confirmed working (rename to awww tracked in nixpkgs #478051)
- `pkgs.jq` — for parsing `hyprctl monitors -j` output
- `~/Pictures/Wallpapers/` and `~/Videos/Wallpapers/` directories (created by wallpaper-init)

**Risks:**

| Risk | Severity | Mitigation |
|------|----------|------------|
| mpvpaper memory leak on loop ([#101](https://github.com/GhostNaN/mpvpaper/issues/101)) | High | 30-minute restart wrapper + `gpu-api=vulkan` |
| mpvpaper wakes dGPU via cuda probe ([mpv#13668](https://github.com/mpv-player/mpv/issues/13668)) | Medium | Battery auto-switch disables video on battery; accept draw on AC |
| swww rename to awww | Low | Package still `pkgs.swww` with alias; update when nixpkgs changes |
| Race condition on Video exit | Low | Poll `swww query` instead of blind `sleep 1` |
| 4K animated GIF memory blow-up | Medium | Document in rofi menu help; recommend resizing with `gifsicle` |
| mpvpaper segfaults after extended runtime ([#84](https://github.com/GhostNaN/mpvpaper/issues/84)) | Medium | Restart wrapper handles this automatically |

## Sources & References

### Origin

- **Brainstorm document:** [docs/brainstorms/2026-03-02-animated-wallpapers-brainstorm.md](docs/brainstorms/2026-03-02-animated-wallpapers-brainstorm.md) — Key decisions: multi-tool stack (swww + mpvpaper), rofi menu switching, battery auto-switch with manual override.

### Internal References

- Existing swww setup: `home/linux/hyprland.nix:14,34-35`
- Rofi config: `home/linux/rofi.nix:1-14`
- Hyprland keybinds: `home/linux/hyprland.nix:51-86`
- Power management: `modules/nixos/power.nix:1-20`
- Hypridle config: `home/linux/hyprlock.nix:87-100`
- Module import pattern: `home/linux/default.nix:1-12`

### External References — mpvpaper

- [mpvpaper GitHub](https://github.com/GhostNaN/mpvpaper)
- [#65 — Nvidia GPU support](https://github.com/GhostNaN/mpvpaper/issues/65) — maintainer confirms `vo=libmpv` only
- [#75 — dGPU wake on Optimus](https://github.com/GhostNaN/mpvpaper/issues/75) — cuda probe issue
- [#101 — Memory leak on loop (OPEN)](https://github.com/GhostNaN/mpvpaper/issues/101) — Nvidia+OpenGL root cause
- [#84 — Segfaults after extended runtime](https://github.com/GhostNaN/mpvpaper/issues/84)
- [mpv#15099 — Nvidia+OpenGL memory leak](https://github.com/mpv-player/mpv/issues/15099)
- [mpv#13668 — cuda probe wakes dGPU](https://github.com/mpv-player/mpv/issues/13668)
- [mpvpaper-stop — Hyprland-aware auto-pause](https://github.com/pvtoari/mpvpaper-stop)

### External References — swww/awww

- [awww on Codeberg](https://codeberg.org/LGFae/awww) — current active repo
- [swww on GitHub (archived)](https://github.com/LGFae/swww)
- [Rename blog post](https://www.lgfae.com/posts/2025-10-29-RenamingSwww.html)
- [nixpkgs rename tracking #459434](https://github.com/nixos/nixpkgs/issues/459434)
- [#444 — Daemon readiness / wait for socket](https://github.com/LGFae/swww/issues/444)

### External References — Rofi

- [rofi-script(5) man page](https://man.archlinux.org/man/rofi-script.5.en) — script mode protocol
- [JaKooLit/Hyprland-Dots WallpaperSelect.sh](https://deepwiki.com/JaKooLit/Hyprland-Dots/4.2-rofi-menus) — community wallpaper picker example

### External References — Battery Detection

- [Power Management — ArchWiki](https://wiki.archlinux.org/title/Power_management)
- [NixOS Wiki — Power Management](https://wiki.nixos.org/wiki/Power_Management)
