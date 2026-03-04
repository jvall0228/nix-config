# Brainstorm: HyprPanel Feature Parity

**Date:** 2026-03-02
**Status:** Decided

## What We're Building

A rich desktop shell experience matching HyprPanel's feature set using a **hybrid Waybar + AGS/Astal** approach:

- **Waybar** stays as the status bar — add missing modules (RAM, CPU temp, GPU, disk, weather, updates counter, night light toggle, idle inhibitor)
- **AGS/Astal** provides rich interactive widgets — dashboard panel, drop-down menus (audio mixer, network picker, bluetooth manager, media player, calendar), and enhanced notification center

## Why This Approach

### Why not replace Waybar entirely with AGS?
Waybar already works, is Stylix-themed, has instant startup, and low resource usage. Rewriting the bar from scratch is wasted effort.

### Why AGS/Astal for the interactive layer?
- First-class home-manager module + flake — fits the declarative NixOS workflow
- TypeScript/JSX is well-tooled and practical
- Signal-based reactivity via Astal services (no polling scripts)
- HyprPanel itself is built on Astal — proven it can achieve full parity
- Handles Wayland popups natively (unlike EWW which struggles with click-outside-to-close)

### Why not the alternatives?
- **EWW** — Wayland popup limitations are a dealbreaker for drop-down menus and dashboard
- **Fabric** — Ax-Shell (most visible showcase) archived Jan 2026; GTK3-only is a dead end
- **Quickshell** — Best UI model (QML), but alpha status + Qt/GTK theming friction with Stylix makes it risky now
- **Pure Waybar** — Hard ceiling on interactive UI; can't do rich popups, dashboards, or live-updating drop-down menus

## Key Decisions

1. **Hybrid architecture** — Waybar for bar, AGS/Astal for interactive widgets
2. **Incremental rollout** — add Waybar modules first (quick win), then build AGS widgets one at a time
3. **AGS v3.x / Astal** — use current version, not deprecated v1
4. **Waybar on-click integration** — wire AGS popups to Waybar module clicks

## Feature Gap Inventory

### Waybar Module Additions (Quick Wins)
- [ ] RAM usage module
- [ ] CPU temperature module
- [ ] GPU usage/temp (NVIDIA)
- [ ] Disk/storage module
- [ ] Weather widget (custom module + script or wttrbar)
- [ ] Updates counter (custom module)
- [ ] Hyprsunset (night light) toggle
- [ ] Hypridle toggle
- [ ] Backlight/brightness module
- [ ] Keyboard layout indicator

### AGS/Astal Interactive Widgets (Build Over Time)
- [ ] Calendar popover (click clock → rich calendar with events)
- [ ] Audio mixer drop-down (per-app volume, input/output device picker)
- [ ] Network menu (WiFi scanner, saved networks, VPN toggle)
- [ ] Bluetooth manager popup (device list, connect/disconnect)
- [ ] Media player controls (album art, progress bar, shuffle/repeat)
- [ ] Dashboard panel (user profile, quick settings, shortcuts, system overview)
- [ ] Enhanced notification center (with media controls and volume slider embedded)
- [ ] Power profiles menu (performance/balanced/power-saver)

### Other Missing Pieces
- [ ] Cava audio visualizer (can be a Waybar custom module or AGS widget)
- [ ] Screen recording keybind (wl-screenrec is installed but unbound)
- [ ] Color picker keybind (hyprpicker is installed but unbound)
- [ ] Emoji picker (rofi-emoji or AGS widget)
- [ ] Window switcher (rofi -show window or AGS)
- [ ] SwayOSD client integration (current keybinds use wpctl/brightnessctl directly)

## Implementation Order

1. **Phase 1: Waybar modules** — Enable built-in modules, add custom script modules. No new dependencies.
2. **Phase 2: AGS/Astal scaffolding** — Add flake inputs, home-manager module, basic project structure. Get a "hello world" popup working.
3. **Phase 3: First AGS widget** — Calendar popover triggered from Waybar clock click. Proves the integration pattern.
4. **Phase 4: System menus** — Audio mixer, network, bluetooth drop-downs. One at a time.
5. **Phase 5: Dashboard** — Central control panel with quick settings, shortcuts, system overview.
6. **Phase 6: Notification center** — Enhanced swaync replacement or overlay with media/volume widgets.

## Technical Notes

### AGS/Astal NixOS Integration
```nix
# flake.nix inputs needed:
inputs.astal.url = "github:aylur/astal/main";
inputs.ags.url = "github:aylur/ags";

# home-manager module:
imports = [ inputs.ags.homeManagerModules.default ];
programs.ags = {
  enable = true;
  configDir = ./ags-config;
  extraPackages = with inputs.astal.packages.${pkgs.system}; [
    astal3 astal4 astal-io
    battery network bluetooth
    # add service libraries as needed
  ];
};
```

### Waybar ↔ AGS Communication
- Waybar `on-click` calls `ags toggle <window-name>` to open/close AGS popups
- AGS windows use layer-shell anchoring to position near the relevant Waybar module
- Both share Stylix theming (AGS via GTK, Waybar via Stylix target)

## Open Questions

None — all major decisions resolved.

## Future Consideration

**Revisit Quickshell (QML/Qt6) in late 2026.** It has the best UI model of all options (QML was purpose-built for UIs, live reload, efficient Qt rendering) and the fastest-growing community. Current blockers are alpha stability and Qt/GTK Stylix theming friction. If Quickshell reaches stable and the theming story improves, it could replace both Waybar and AGS as a unified shell.
