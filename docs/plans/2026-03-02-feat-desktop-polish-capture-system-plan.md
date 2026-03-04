---
title: "feat: Desktop Polish — CleanShot-style Capture System + Misc Fixes"
type: feat
status: completed
date: 2026-03-02
origin: docs/brainstorms/2026-03-02-desktop-polish-brainstorm.md
---

# feat: Desktop Polish — CleanShot-style Capture System + Misc Fixes

Unified capture menu (screenshots + screen recording) via rofi, color picker keybind, XDG user dirs, logind config, and cleanup.

## Acceptance Criteria

### capture.nix (new module)

- [x] **`home/linux/capture.nix`** — New module following `wallpaper.nix` pattern (`writeShellScriptBin` scripts in `let` block)
- [x] **`capture-menu`** — Rofi script-mode script displaying these options:
  - `Screenshot Region` — `slurp` → `grim -g` → `wl-copy` (clipboard). Notify "Screenshot copied"
  - `Screenshot Fullscreen` — `grim` → save to `~/Pictures/Screenshots/screenshot-YYYYMMDD-HHMMSS.png` AND `wl-copy`. Notify "Screenshot saved to ..."
  - `Record Region` — `slurp` → `wl-screenrec -g --audio` → save to `~/Videos/Recordings/recording-YYYYMMDD-HHMMSS.mp4`. Notify "Recording started"
  - `Record Fullscreen` — `wl-screenrec --audio` → save to `~/Videos/Recordings/recording-YYYYMMDD-HHMMSS.mp4`. Notify "Recording started"
  - `Stop Recording` — Kill active `wl-screenrec` via PID file. Notify "Recording saved to ..."
- [x] **State tracking** via `~/.local/state/capture/recording.pid` (PID) and `recording.path` (output file path)
- [x] **Recording conflict handling** — If a recording is active when starting a new one: stop current first, then start new
- [x] **Slurp cancellation** — Check slurp exit code; exit cleanly with no notification if user cancels (ESC)
- [x] **Stale PID handling** — Verify PID is alive before attempting to kill; clean up stale state files
- [x] **Notifications** via `notify-send` (swaync) for all successful actions
- [x] **Audio capture** — `wl-screenrec --audio` for mic + system audio
- [x] **`mkdir -p`** for output directories before saving

### hyprland.nix changes

- [x] **Add** `"$mod SHIFT, S, exec, capture-menu"` keybind (or rofi script-mode invocation)
- [x] **Add** `"$mod SHIFT, P, exec, hyprpicker -a"` keybind (color picker → hex to clipboard)
- [x] **Remove** 3 Print-key screenshot binds (lines 83-85)
- [x] **Remove** `nautilus` from `home.packages` (line 19, already in `desktop.nix`)

### desktop.nix changes

- [x] **Add** `xdg.userDirs.enable = true` with `createDirectories = true`
- [x] **Set** standard dirs: Documents, Downloads, Music, Pictures, Videos

### power.nix changes (system-level)

- [x] **Add** `services.logind.lidSwitch = "suspend"` (always suspend on lid close)
- [x] **Add** `services.logind.powerKey = "ignore"`
- [x] **Add** `services.logind.powerKeyLongPress = "poweroff"`

### default.nix (imports)

- [x] **Add** `./capture.nix` to `home/linux/default.nix` imports list

### Build

- [x] System rebuilds successfully with `bash apps/build-switch`

## Context

**Key files to modify:**

| File | Change |
|---|---|
| `home/linux/capture.nix` | **New** — capture menu scripts |
| `home/linux/default.nix` | Add `./capture.nix` to imports |
| `home/linux/hyprland.nix` | Add 2 keybinds, remove 3 Print binds + nautilus |
| `home/linux/desktop.nix` | Add XDG user dirs |
| `modules/nixos/power.nix` | Add logind settings |

**Architecture pattern:** Follow `wallpaper.nix` — `pkgs.writeShellScriptBin` in `let` block, scripts as `home.packages`, state files in `~/.local/state/capture/`. All runtime deps (grim, slurp, wl-screenrec, wl-clipboard, libnotify) are already in `home.packages` via `hyprland.nix`.

**Capture menu keybind pattern** (like wallpaper menu):
```
$mod SHIFT, S, exec, sh -c 'rofi -show capture -modi "capture:capture-menu" ...'
```

**Decisions from brainstorm** (see brainstorm: `docs/brainstorms/2026-03-02-desktop-polish-brainstorm.md`):
- Single SUPER+SHIFT+S replaces all Print-key binds
- New `capture.nix` module (not inline in hyprland.nix)
- SUPER+SHIFT+P for color picker

**SpecFlow resolutions:**
- Recording conflict: stop current, start new
- Slurp cancel: exit cleanly, no notification
- Lid switch: always suspend (no special docked behavior)
- Audio: mic + system via `--audio`
- Notifications: yes, brief, via notify-send/swaync
- File format: MP4, H.264 default codec

## Sources

- **Origin brainstorm:** [docs/brainstorms/2026-03-02-desktop-polish-brainstorm.md](docs/brainstorms/2026-03-02-desktop-polish-brainstorm.md)
- Pattern reference: `home/linux/wallpaper.nix` (writeShellScriptBin + state files + rofi script-mode)
- Keybind reference: `home/linux/hyprland.nix:50-86` (existing bind patterns)
