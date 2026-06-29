---
status: pending
priority: p2
issue_id: "006"
tags: [ux, hyprland, ags, waybar, walker, rofi, stylix, thinkpad, rice]
dependencies: []
---

# Improve ThinkPad Desktop UX with Desktop Modes and Clear Surface Ownership

## Problem Statement

The ThinkPad desktop is already feature-rich: Hyprland, Waybar, AGS/Astal, Walker, Rofi, Stylix, Hyprlock, animated wallpapers, capture tooling, and ThinkPad power policy are all present. The remaining UX gap is not missing baseline components; it is that several flows are not yet unified into a cohesive desktop model.

Specific gaps:

- Wallpaper switching exists, but there is no whole-desktop mode/profile layer.
- Capture has overlapping entry points: Hyprland direct record toggle, Rofi capture menu, and AGS dashboard screen recording.
- Walker and Rofi both cover launching/search-like behavior; their responsibilities should be clearer.
- AGS dashboard has useful basics but does not yet expose the most valuable ThinkPad/workstation context.
- Wlogout and AGS both expose session/power actions; decide whether this is intentional redundancy or should be consolidated.
- Stylix is the durable theme source, but there is no runtime UX profile system for temporary visual/behavioral modes.

## Design Artifacts

Static visual guides were created to make this implementable by another agent without redoing the research:

- `docs/visual-guides/thinkpad-ux/index.html` — overview and framework boundaries
- `docs/visual-guides/thinkpad-ux/desktop-modes.html` — desktop mode/profile switcher concept
- `docs/visual-guides/thinkpad-ux/command-center.html` — AGS command center/dashboard expansion concept
- `docs/visual-guides/thinkpad-ux/ownership-map.html` — ownership boundaries for Waybar, AGS, Walker, Rofi, and Stylix
- `docs/visual-guides/thinkpad-ux/README.md` — constraints and recommended direction

Open `docs/visual-guides/thinkpad-ux/index.html` in a browser to inspect the full guide.

## Current Architecture to Preserve

Do not introduce another UX framework unless there is a very strong reason. The desired convention is:

- **Hyprland** — compositor, keybinds, window rules, runtime keywords
- **Waybar** — glanceable status and AGS popup launch points
- **AGS/Astal** — rich interactive widgets, dashboard, popups, notifications, OSD
- **Walker** — universal launcher/search surface
- **Rofi** — scoped task menus such as wallpaper, capture, desktop mode, and maintenance actions
- **Stylix** — durable/declarative theme authority
- **Hyprlock** — lock surface and agent-aware lockscreen

Avoid adding or switching to:

- Quickshell
- EWW
- Polybar
- A second notification center
- pywal/wpgtk as a competing theme authority
- A second power management policy layer besides TLP

## Proposed Solution

### 1. Add Desktop Modes

Create a small desktop-mode layer around existing wallpaper state and reload hooks.

Suggested modes:

- **daily** — current Tokyo Night defaults, normal animations, normal Waybar/AGS density
- **thinkpad-red** — black/red TrackPoint-inspired accent profile for screenshots and visual polish
- **battery** — static wallpaper, reduced animations, quieter polling, battery-first dashboard emphasis
- **focus** — DND, reduced bar noise, explicit idle/lock state, fewer visual distractions
- **desk** — AC-powered mode with video wallpaper and full visual effects
- **showcase** — opens a curated unixporn-ready layout and optionally starts capture

Implementation direction:

- Store mode in `~/.local/state/desktop-mode/current`.
- Add a `desktop-mode` script with `set`, `get`, `toggle`, and `apply` subcommands.
- Reuse the existing wallpaper scripts rather than replacing them.
- Use runtime-generated CSS/overrides for AGS and Waybar where needed.
- Use `hyprctl keyword` for runtime animation/gap/border tweaks where practical.
- Keep permanent/durable theme choices in Stylix/Nix.

### 2. Expand AGS Dashboard into a ThinkPad Command Center

Build on the existing AGS dashboard rather than adding another shell.

Useful additions:

- Current desktop mode tile and picker entry point
- TLP state: AC/BAT policy, charge threshold display, current platform profile if available
- Battery health and estimated time where available
- NVIDIA runtime state/offload state
- Syncthing status
- Tailscale status when enabled
- Capture status: active recording, stop button, reveal latest file
- Agent state summary matching existing Waybar/lockscreen agent status
- Last screenshot/recording shortcuts

Keep existing AGS popups for calendar, audio, network, Bluetooth, media, notifications, and OSD.

### 3. Consolidate Capture Ownership

Make the Rofi capture menu the canonical capture start flow.

Desired ownership:

- Rofi capture menu starts screenshots and recordings.
- AGS dashboard shows capture state, stops active recording, and opens/reveals latest capture.
- Waybar may show a small recording indicator if active.
- Remove or redirect the direct Hyprland `SUPER+SHIFT+R` recording toggle after the canonical flow is proven.
- Avoid AGS writing recordings to `/tmp/recording.mp4`; use the same state/path files as the capture menu.

### 4. Clarify Launcher/Menu Ownership

Desired convention:

- Walker (`SUPER+SPACE`) is the universal launcher/search surface: apps, files, windows, clipboard, symbols, calc, web search.
- Rofi is for constrained menus: wallpaper, capture, desktop mode, maintenance/debug actions.
- Once Walker is trusted, consider de-emphasizing or removing the Rofi app-launch keybind to avoid duplicate app-launch UX.

### 5. Decide Power/Session Surface Ownership

Current state has both Wlogout and AGS session actions. Decide between:

- Keep both intentionally: Wlogout as dedicated full-screen power menu, AGS as quick dashboard actions.
- Or consolidate: AGS owns session actions and Wlogout becomes fallback only.

Any implementation must respect the existing TLP policy in `modules/nixos/power.nix`; do not add power-profiles-daemon as a competing policy layer.

## Relevant Files

- `home/linux/hyprland.nix` — keybinds, startup, Hyprland runtime behavior
- `home/linux/waybar.nix` — status modules and AGS click-throughs
- `home/linux/ags.nix` — AGS module wiring and Stylix color export
- `home/linux/ags/app.ts` — registered AGS widgets and request handler
- `home/linux/ags/widgets/Dashboard.tsx` — command center target
- `home/linux/ags/widgets/Notifications.tsx` — current notification owner
- `home/linux/wallpaper.nix` — existing wallpaper state and battery-aware wallpaper behavior
- `home/linux/capture.nix` — canonical capture menu candidate
- `home/linux/walker.nix` — universal launcher/search configuration
- `home/linux/rofi.nix` — Rofi task-menu base
- `home/linux/wlogout.nix` — current dedicated power menu
- `modules/shared/stylix.nix` — durable theme source
- `modules/nixos/power.nix` — TLP/logind policy
- `docs/visual-guides/thinkpad-ux/` — visual planning artifacts

## Acceptance Criteria

- [ ] Desktop modes exist with at least `daily`, `battery`, `focus`, and `thinkpad-red`
- [ ] Mode state survives session restart and is visible from AGS dashboard
- [ ] Mode changes update wallpaper behavior and at least one visual surface (AGS, Waybar, or Hyprland accent)
- [ ] `battery` mode prevents or disables video wallpaper and reduces visual/polling cost
- [ ] AGS dashboard shows ThinkPad/workstation context beyond generic CPU/RAM/disk stats
- [ ] Capture has one canonical start flow and no competing recording-to-`/tmp` path
- [ ] Active recording state is visible and stoppable from AGS or Waybar
- [ ] Walker and Rofi responsibilities are documented in code comments or docs
- [ ] No new UX framework is introduced
- [ ] Stylix remains the only durable/declarative theme authority
- [ ] Existing AGS popups, Waybar status, wallpaper restore, and Hyprlock behavior still work
- [ ] Nix/Home Manager config builds successfully

## Suggested Implementation Order

1. Implement a minimal `desktop-mode` script and state directory without changing visuals.
2. Add a Rofi desktop-mode menu or AGS dashboard mode tile that calls the script.
3. Wire `battery` mode into existing wallpaper behavior.
4. Add mode-aware AGS/Waybar CSS accents.
5. Add AGS dashboard ThinkPad/workstation status tiles.
6. Consolidate capture state between `capture-menu` and AGS dashboard.
7. Review keybinds and de-duplicate launcher/capture/power entry points.

## Validation Notes

- Check HTML guide pages visually before implementing; they are design guides, not generated UI.
- Test mode changes on AC and battery.
- Test recording start/stop/reveal paths.
- Test AGS under the current hybrid GPU workaround before adding more widgets.
- Verify `home-manager`/NixOS builds after each module change.

## Work Log

| Date | Action | Result |
|---|---|---|
| 2026-06-28 | Researched unixporn-inspired UX gaps and compared against current repo state | Determined mode/profile switching and AGS dashboard expansion are the highest-value improvements |
| 2026-06-28 | Created visual guide artifacts in `docs/visual-guides/thinkpad-ux/` | Static HTML/CSS guide is ready for handoff |
