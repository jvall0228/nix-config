# ThinkPad UX Visual Guide

Static planning artifacts for improving the current NixOS ThinkPad desktop UX without adding redundant runtime frameworks.

## Files

- `index.html` - overview and current-framework boundaries.
- `desktop-modes.html` - proposed runtime mode/profile switcher.
- `command-center.html` - proposed AGS dashboard expansion.
- `ownership-map.html` - UX ownership boundaries for Waybar, AGS, Walker, Rofi, and Stylix.
- `common.css` - shared styling for the mockups.

## Design Constraints

- Keep the existing architecture: Hyprland, Waybar, AGS/Astal, Walker, Rofi, Stylix.
- Do not add Quickshell, EWW, Polybar, another notification center, or another theme authority.
- Borrow interaction ideas from other unixporn rices by mapping them into the current stack.
- Treat these files as visual guides only. They do not modify live NixOS, Home Manager, Hyprland, AGS, or Waybar configuration.

## Recommended Direction

1. Add a desktop-mode layer around existing wallpaper state.
2. Expand the AGS dashboard into a ThinkPad/workstation command center.
3. Consolidate capture ownership so Rofi starts capture and AGS reports/stops/reveals capture state.
4. Make Walker the default universal launcher/search surface and Rofi the scoped task-menu surface.
5. Keep Stylix as the durable theme authority, with runtime modes limited to generated CSS, Hyprland keywords, and wallpaper state.
