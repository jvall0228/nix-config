# Desktop Polish Brainstorm

**Date:** 2026-03-02
**Status:** Draft

## What We're Building

A set of desktop environment improvements focused on two areas:

### 1. CleanShot-style Capture System

A unified capture menu (like macOS CleanShot's Cmd+Shift+5) accessible via **SUPER+SHIFT+S** that opens a rofi menu offering:

- **Screenshot Region** — Select area, copy to clipboard
- **Screenshot Fullscreen** — Capture entire screen, save to ~/Pictures/Screenshots/
- **Record Region** — Select area, start recording (toggle to stop)
- **Record Fullscreen** — Record entire screen (toggle to stop)
- **Stop Recording** — Stop any active recording

Recordings save to `~/Videos/Recordings/` with timestamped filenames. Uses existing tools: `grim`, `slurp`, `wl-screenrec`, `wl-copy`.

This **replaces** the current three Print-key screenshot binds in `hyprland.nix` (lines 83-85) with the single SUPER+SHIFT+S menu.

### 2. Color Picker + Misc Fixes

- **Hyprpicker keybind** — SUPER+SHIFT+P to pick a color and copy hex to clipboard
- **XDG user directories** — Ensure Documents, Downloads, Pictures, Videos, Music exist
- **Logind behavior** — Configure lid switch (suspend) and power button (ignore on press, poweroff on long-press)
- **Deduplicate Nautilus** — Remove from `hyprland.nix` line 19 (already in `desktop.nix` line 22)

## Why This Approach

**New `capture.nix` module** rather than extending `hyprland.nix`:

- Capture logic (rofi script, recording state management) is complex enough to warrant its own module
- Keeps `hyprland.nix` focused on window management
- Follows the repo pattern of dedicated modules per concern (like `wallpaper.nix`)
- The capture script needs state tracking (is a recording active?) which is distinct from keybind config

## Key Decisions

1. **Single keybind (SUPER+SHIFT+S)** replaces all three Print-key binds — unified entry point
2. **Rofi menu** for capture mode selection — consistent with wallpaper picker UX
3. **New `home/linux/capture.nix`** module — clean separation of concerns
4. **wl-screenrec** for recording — already installed, Wayland-native, low overhead
5. **SUPER+SHIFT+P** for color picker — doesn't conflict with existing binds
6. **XDG dirs and logind** go in existing modules (not capture.nix) — they're unrelated to capture

## Scope

### In Scope
- Capture rofi menu script + keybind
- Hyprpicker keybind
- XDG user directories config
- Logind lid/power button behavior
- Remove duplicate Nautilus package

### Out of Scope
- Night mode / blue light filter (gammastep)
- Window rules
- Backup/snapshot system
- GPU/battery improvements
