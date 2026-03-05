---
title: "feat: Add context panel button to waybar (leftmost position)"
type: feat
status: todo
date: 2026-03-05
related: docs/plans/2026-03-02-feat-hyprpanel-parity-waybar-ags-plan.md
---

# feat: Add Context Panel Button to Waybar

## Summary

Add a context panel button on the **leftmost side** of waybar, similar to HyprPanel's sidebar launcher. The button should display the user avatar and open a panel with quick-access buttons.

## Requirements

### Button (Waybar Module)
- Position: leftmost in `modules-left` (before `hyprland/workspaces`)
- Shows the user's avatar image (rounded, ~28px to fit bar height of 36px)
- On click: opens an AGS context panel popup
- Module type: `custom/panel` or `image` module

### Context Panel (AGS Popup)
- Triggered by the waybar button click via `ags request toggle panel`
- Anchored to the top-left corner of the screen
- Contains:
  - **User section** — larger avatar, username, hostname
  - **Quick action buttons** — power menu (shutdown, reboot, suspend, logout, lock), settings shortcuts
  - **Session controls** — night light toggle, idle inhibitor toggle, do-not-disturb toggle
  - **System info** — uptime, NixOS generation, kernel version
- Follows the existing popup pattern: singleton (closes other popups), click-outside-to-close, CSS slide+fade animation
- Themed via Stylix `colors.css` (same as other AGS widgets)

## Implementation Notes

- The user avatar can be stored in `assets/` (e.g., `assets/avatar.png`)
- Waybar `image` module or `custom/panel` module with `return-type: json` and an `<img>` element
- Follows the existing hybrid architecture: waybar button + AGS popup
- Power actions use existing `wlogout` bindings or direct `systemctl` / `hyprctl dispatch exit` commands
- Middle-click fallback on the button could open `wlogout` directly

## References

- HyprPanel sidebar: user avatar + power/session buttons
- Existing AGS popup pattern: `home/linux/ags/`
- Waybar config: `home/linux/waybar.nix`
- Brainstorm: `docs/brainstorms/2026-03-02-hyprpanel-parity-brainstorm.md`
