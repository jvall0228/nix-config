---
title: "feat: HyprPanel Feature Parity via Hybrid Waybar + AGS/Astal"
type: feat
status: active
date: 2026-03-02
origin: docs/brainstorms/2026-03-02-hyprpanel-parity-brainstorm.md
---

# feat: HyprPanel Feature Parity via Hybrid Waybar + AGS/Astal

## Overview

Build a rich desktop shell experience matching HyprPanel's feature set using a **hybrid architecture**: Waybar remains the status bar (with additional modules), and AGS v3/Astal provides rich interactive widgets — dashboard, drop-down menus, media controls, and notification center.

This is an incremental rollout across 6 phases, starting with zero-risk Waybar module additions and progressing to full AGS integration. (see brainstorm: `docs/brainstorms/2026-03-02-hyprpanel-parity-brainstorm.md`)

## Problem Statement / Motivation

The current desktop shell is functional but limited compared to HyprPanel:
- No rich popups (calendar, audio mixer, network scanner, bluetooth manager)
- No central dashboard with quick settings
- Minimal Waybar modules (missing RAM, GPU, temp, weather, etc.)
- No unified notification center with embedded media/volume controls
- Click actions on Waybar modules either do nothing or open heavyweight external apps (e.g., `blueman-manager`)

## Proposed Solution

**Hybrid architecture** (see brainstorm: Key Decisions #1-4):
1. **Keep Waybar** as the status bar — add missing built-in modules, update `on-click` handlers
2. **Add AGS v3/Astal** for interactive layer-shell widgets triggered by Waybar clicks
3. **Replace swaync** with AGS notification daemon for a unified notification center
4. **Replace swayosd-server** with AGS OSD overlays for visual consistency
5. **Remove tray applets** (nm-applet, blueman-applet) once AGS equivalents are stable

## Resolved Design Questions

The SpecFlow analysis surfaced 13 gaps. Here are the resolutions:

### Critical Resolutions

| Question | Resolution | Rationale |
|---|---|---|
| AGS v1 or v2? | **AGS v3.x (Astal-based)** | Actively developed, TypeScript/JSX, first-class NixOS flake. Decided in brainstorm. |
| Replace swaync? | **Yes, AGS replaces swaync** | Two notification daemons cannot coexist on D-Bus. AGS notification center enables Flow 6. |
| Waybar ↔ AGS IPC? | **CLI: `ags request "toggle:<widget>"`** | Simplest approach. Waybar `on-click` runs the command. No custom D-Bus needed. |
| Multi-monitor popups? | **AGS reads focused monitor from Hyprland IPC** | `hyprctl monitors -j` at popup-open time determines correct output. |

### Important Resolutions

| Question | Resolution | Rationale |
|---|---|---|
| TLP vs power-profiles-daemon? | **Keep TLP, build custom AGS widget** | Charge thresholds (`START=20, STOP=80`) are too valuable on a laptop. Custom widget wraps `tlp-stat`. |
| nm-applet / blueman-applet? | **Remove once AGS equivalents are stable** | Redundant with AGS network/bluetooth widgets. Keep packages for CLI tools (`nmcli`, `bluetoothctl`). |
| Graceful degradation? | **Click = AGS popup, middle-click = direct action** | Click opens rich popup. Middle-click preserves standalone functionality (mute toggle, etc.) as fallback. |
| Waybar modules to add? | **memory, temperature, custom/gpu, backlight, idle_inhibitor** | See Phase 1 for full list. |
| Stylix → AGS colors? | **Build-time CSS generation via `config.lib.stylix.colors`** | Nix reads Stylix palette, generates `colors.css` imported by AGS widgets. |

### UX Resolutions

| Question | Resolution | Rationale |
|---|---|---|
| Dashboard keybind? | **`$mod + A`** | Intuitive, available, doesn't conflict with existing binds. |
| Popup animations? | **CSS transitions (slide + fade, 200ms)** | Independent of Hyprland animation config. Controlled within AGS. |
| Notification persistence? | **No persistence across reboots** | Ephemeral, matching swaync's current behavior. |
| swayosd-server? | **Replace with AGS OSD overlays** | Visual consistency. AGS handles volume/brightness OSD. |
| Popup mutual exclusion? | **Singleton: opening any popup closes all others** | `closeAllPopups()` called before `togglePopup()`. Only one popup at a time. |

## Technical Approach

### Architecture

```
┌─────────────────────────────────────────────────────┐
│                    Hyprland                          │
│                                                      │
│  ┌──────────────────────────────────────────────┐   │
│  │              Waybar (top bar)                 │   │
│  │  workspaces | window | clock | mpris | vol    │   │
│  │  net | bt | bat | cpu | mem | temp | tray     │   │
│  │           on-click → ags request              │   │
│  └──────────────────────────────────────────────┘   │
│                        │                             │
│                        ▼                             │
│  ┌──────────────────────────────────────────────┐   │
│  │           AGS/Astal (layer-shell)             │   │
│  │                                                │   │
│  │  ┌──────────┐ ┌─────────┐ ┌──────────────┐   │   │
│  │  │ Calendar │ │  Audio  │ │   Network    │   │   │
│  │  │ Popover  │ │  Mixer  │ │   Scanner    │   │   │
│  │  └──────────┘ └─────────┘ └──────────────┘   │   │
│  │  ┌──────────┐ ┌─────────┐ ┌──────────────┐   │   │
│  │  │Bluetooth │ │  Media  │ │  Dashboard   │   │   │
│  │  │ Manager  │ │ Player  │ │   Panel      │   │   │
│  │  └──────────┘ └─────────┘ └──────────────┘   │   │
│  │  ┌──────────┐ ┌─────────┐                     │   │
│  │  │  Notif   │ │   OSD   │                     │   │
│  │  │  Center  │ │ Overlay │                     │   │
│  │  └──────────┘ └─────────┘                     │   │
│  └──────────────────────────────────────────────┘   │
│                                                      │
│  ┌────────────┐ ┌────────────┐ ┌────────────────┐   │
│  │   Rofi     │ │  Hyprlock  │ │   Wlogout      │   │
│  │ (launcher) │ │  (lock)    │ │  (power menu)  │   │
│  └────────────┘ └────────────┘ └────────────────┘   │
└─────────────────────────────────────────────────────┘
```

### Stylix Color Bridge

AGS has no Stylix target. Colors are bridged at Nix build time:

```nix
# In home/linux/ags.nix
let
  colors = config.lib.stylix.colors;
  colorsCss = pkgs.writeText "colors.css" ''
    :root {
      --base00: #${colors.base00}; /* background */
      --base01: #${colors.base01}; /* lighter bg */
      --base02: #${colors.base02}; /* selection */
      --base03: #${colors.base03}; /* comments */
      --base04: #${colors.base04}; /* dark fg */
      --base05: #${colors.base05}; /* foreground */
      --base06: #${colors.base06}; /* light fg */
      --base07: #${colors.base07}; /* lightest fg */
      --base08: #${colors.base08}; /* red */
      --base09: #${colors.base09}; /* orange */
      --base0A: #${colors.base0A}; /* yellow */
      --base0B: #${colors.base0B}; /* green */
      --base0C: #${colors.base0C}; /* cyan */
      --base0D: #${colors.base0D}; /* blue */
      --base0E: #${colors.base0E}; /* purple */
      --base0F: #${colors.base0F}; /* brown */

      --font-mono: "JetBrainsMono Nerd Font";
      --font-sans: "Noto Sans";
      --border-radius: 8px;
    }
  '';
in ...
```

### Waybar ↔ AGS Communication Pattern

```nix
# Waybar module on-click wiring (in waybar.nix)
clock = {
  format = "{:%H:%M  %a %b %d}";
  on-click = "ags request 'toggle:calendar'";        # AGS popup
  on-middle-click = "";                                # no standalone action
};

pulseaudio = {
  format = "{volume}% {icon}";
  on-click = "ags request 'toggle:audiomixer'";       # AGS popup
  on-middle-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";  # fallback
};

network = {
  on-click = "ags request 'toggle:network'";          # AGS popup
  on-middle-click = "nmcli radio wifi on";             # fallback
};

bluetooth = {
  on-click = "ags request 'toggle:bluetooth'";        # AGS popup
  on-middle-click = "bluetoothctl power toggle";       # fallback
};
```

### AGS Widget Structure

Each widget is a TypeScript/TSX file in the AGS config directory:

```
home/linux/ags/
├── app.ts              # Entry point — registers all windows
├── style.css           # Imports colors.css, global styles
├── lib/
│   ├── popups.ts       # Singleton popup manager (closeAll, toggle)
│   └── utils.ts        # Shared utilities (monitor detection, etc.)
├── widgets/
│   ├── Calendar.tsx    # Calendar popover
│   ├── AudioMixer.tsx  # Per-app volume, device picker
│   ├── Network.tsx     # WiFi scanner, connect/disconnect
│   ├── Bluetooth.tsx   # Device list, pair/connect
│   ├── Media.tsx       # Album art, progress, controls
│   ├── Dashboard.tsx   # Profile, quick settings, shortcuts, stats
│   ├── Notifications.tsx  # Notification popup + center
│   └── OSD.tsx         # Volume/brightness on-screen display
└── colors.css          # Generated by Nix from Stylix (symlinked)
```

### Implementation Phases

#### Phase 1: Waybar Module Additions

**Scope:** Zero new dependencies. Enable built-in Waybar modules and add custom script modules.

**Files modified:**
- `/home/javels/nix-config/home/linux/waybar.nix` — add modules

**Modules to add:**

| Module | Type | Config |
|---|---|---|
| `memory` | Built-in | `format = "{}% "` |
| `temperature` | Built-in | `hwmon-path-abs` for CPU, `critical-threshold = 80` |
| `backlight` | Built-in | `format = "{percent}% {icon}"`, `on-scroll-up/down = brightnessctl set 5%+/-` |
| `idle_inhibitor` | Built-in | Toggle icon, prevents screen lock |
| `custom/gpu` | Custom script | `nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits` every 5s |
| `custom/weather` | Custom script | `wttrbar` or `curl wttr.in/?format=...` every 30min |
| `custom/updates` | Custom script | `nix-channel --update && nix-env -u --dry-run 2>&1 | wc -l` or similar, interval 3600s |
| `disk` | Built-in | `format = "{percentage_used}% "`, path `/` |

**Updated modules-right ordering:**
```nix
modules-right = [
  "mpris"
  "idle_inhibitor"
  "custom/weather"
  "backlight"
  "pulseaudio"
  "network"
  "bluetooth"
  "battery"
  "cpu"
  "memory"
  "temperature"
  "custom/gpu"
  "disk"
  "tray"
];
```

**Also in Phase 1 — bind missing keybinds (in hyprland.nix):**
- Screen recording: `$mod + SHIFT + R` → `wl-screenrec -f ~/Videos/recording-$(date +%Y%m%d-%H%M%S).mp4` (toggle with PID check)
- Color picker: `$mod + SHIFT + C` → `hyprpicker -a` (copy to clipboard)
- Window switcher: `ALT + TAB` → `rofi -show window`
- Emoji picker: `$mod + .` → `rofi -show emoji -modi emoji` (requires `rofi-emoji` package)

**Acceptance criteria:**
- [ ] All new Waybar modules render correctly with Stylix theming
- [ ] GPU temp module works for NVIDIA (`nvidia-smi` available)
- [ ] Weather module updates without errors
- [ ] Idle inhibitor toggles hypridle
- [ ] All new keybinds function
- [ ] No regressions in existing modules
- [ ] `nixos-rebuild switch` succeeds

---

#### Phase 2: AGS/Astal Scaffolding

**Scope:** Add flake inputs, home-manager module, basic project structure. Get a "hello world" test popup working.

**Files modified:**
- `/home/javels/nix-config/flake.nix` — add `ags` and `astal` inputs
- `/home/javels/nix-config/home/linux/default.nix` — import ags.nix
- `/home/javels/nix-config/home/linux/ags.nix` — new file (home-manager AGS config)
- `/home/javels/nix-config/home/linux/ags/` — new directory (TypeScript widget source)
- `/home/javels/nix-config/home/linux/hyprland.nix` — add `ags run` to exec-once

**Step 2a: Flake inputs** (`flake.nix`, after line 28):

```nix
ags = {
  url = "github:Aylur/ags";
  inputs.nixpkgs.follows = "nixpkgs";
};
astal = {
  url = "github:Aylur/astal/main";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

No changes needed to `outputs` — `inputs` is already passed via `specialArgs` and `extraSpecialArgs`.

**Step 2b: Home-manager module** (`home/linux/ags.nix`):

```nix
{ pkgs, inputs, config, ... }:
let
  system = pkgs.system;
  colors = config.lib.stylix.colors;
  colorsCss = pkgs.writeText "colors.css" ''
    :root {
      --base00: #${colors.base00};
      /* ... full base16 palette ... */
      --base0F: #${colors.base0F};
      --font-mono: "JetBrainsMono Nerd Font";
      --font-sans: "Noto Sans";
    }
  '';
in {
  imports = [ inputs.ags.homeManagerModules.default ];

  programs.ags = {
    enable = true;
    configDir = ./ags;
    extraPackages = with inputs.astal.packages.${system}; [
      astal3
      astal-io
      battery
      network
      bluetooth
      mpris
      wireplumber
      hyprland
      tray
      notifd
    ];
  };

  # Symlink generated colors.css into AGS config
  xdg.configFile."ags/colors.css".source = colorsCss;
}
```

**Step 2c: Minimal AGS entry point** (`home/linux/ags/app.ts`):

```typescript
import { App } from "astal/gtk3";
import "./style.css";

App.start({
  main() {
    // Phase 3+ widgets registered here
  },
  requestHandler(request, respond) {
    // Waybar on-click handler
    const [action, widget] = request.split(":");
    if (action === "toggle") {
      // Toggle widget window visibility
    }
    respond("ok");
  },
});
```

**Step 2d: Add to exec-once** (`hyprland.nix`):

```nix
"exec-once, ags run"
```

**Acceptance criteria:**
- [ ] `nix flake lock` resolves AGS and Astal inputs
- [ ] `nixos-rebuild switch` succeeds with AGS module enabled
- [ ] AGS daemon starts on login
- [ ] `ags request "hello"` returns a response from the running daemon
- [ ] `colors.css` is generated with correct Stylix colors
- [ ] AGS crash does not affect Waybar functionality

---

#### Phase 3: Calendar Popover (First Widget)

**Scope:** Proves the Waybar → AGS integration pattern end-to-end.

**Files modified:**
- `/home/javels/nix-config/home/linux/ags/widgets/Calendar.tsx` — new
- `/home/javels/nix-config/home/linux/ags/lib/popups.ts` — new (singleton manager)
- `/home/javels/nix-config/home/linux/ags/app.ts` — register Calendar window
- `/home/javels/nix-config/home/linux/waybar.nix` — add `on-click` to clock module

**Calendar widget features:**
- Monthly calendar grid with selectable days
- Current date highlighted
- Month/year navigation (prev/next buttons)
- Anchored to top bar, centered on clock position
- Click-outside or Escape dismisses
- Styled with Stylix base16 colors

**Popup singleton manager (`lib/popups.ts`):**
```typescript
const popups = new Map<string, Widget.Window>();

export function registerPopup(name: string, window: Widget.Window) {
  popups.set(name, window);
}

export function togglePopup(name: string) {
  for (const [key, win] of popups) {
    if (key !== name) win.visible = false;
  }
  const target = popups.get(name);
  if (target) target.visible = !target.visible;
}
```

**Waybar clock update:**
```nix
clock = {
  format = "{:%H:%M  %a %b %d}";
  tooltip-format = "<tt>{calendar}</tt>";
  on-click = "ags request 'toggle:calendar'";
};
```

**Acceptance criteria:**
- [ ] Clicking Waybar clock opens AGS calendar popover
- [ ] Calendar shows correct month/year with today highlighted
- [ ] Month navigation works (prev/next)
- [ ] Clicking outside or pressing Escape closes the calendar
- [ ] Calendar appears on the correct monitor in multi-monitor setup
- [ ] Styled with Tokyo Night Dark colors from Stylix
- [ ] Opening calendar while another popup is open closes the other popup
- [ ] Calendar does not open when screen is locked

---

#### Phase 4: System Menus

**Scope:** Audio mixer, network scanner, bluetooth manager. One at a time. Each follows the same pattern proven in Phase 3.

**Files modified/created per widget:**
- `/home/javels/nix-config/home/linux/ags/widgets/<Widget>.tsx` — new
- `/home/javels/nix-config/home/linux/ags/app.ts` — register window
- `/home/javels/nix-config/home/linux/waybar.nix` — update on-click
- `/home/javels/nix-config/home/linux/hyprland.nix` — remove replaced tray applets when ready

**Phase 4a: Audio Mixer**

Uses Astal's `wireplumber` service library.

Features:
- Master volume slider (output)
- Per-app volume sliders (PipeWire node list)
- Output device picker (speakers, headphones, HDMI, etc.)
- Input device picker (microphone)
- Microphone mute toggle with visual indicator
- Slider changes apply immediately via WirePlumber

Waybar wiring:
```nix
pulseaudio = {
  on-click = "ags request 'toggle:audiomixer'";
  on-middle-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
  on-scroll-up = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+";
  on-scroll-down = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
};
```

**Phase 4b: Network Menu**

Uses Astal's `network` service library.

Features:
- WiFi toggle (on/off)
- Available network list with signal strength bars
- Connected network indicator
- Click to connect (password prompt for secured networks)
- Ethernet status display
- VPN indicator (if active)

Waybar wiring:
```nix
network = {
  on-click = "ags request 'toggle:network'";
  on-middle-click = "sh -c 'nmcli radio wifi $(nmcli radio wifi | grep -q enabled && echo off || echo on)'";
};
```

After stable: remove `nm-applet --indicator` from `exec-once`.

**Phase 4c: Bluetooth Manager**

Uses Astal's `bluetooth` service library.

Features:
- Bluetooth toggle (on/off)
- Paired device list with connection status and battery level
- Click to connect/disconnect
- Scan for new devices
- Forget device option

Waybar wiring:
```nix
bluetooth = {
  on-click = "ags request 'toggle:bluetooth'";
  on-middle-click = "bluetoothctl power toggle";
};
```

After stable: remove `blueman-applet` from `exec-once`.

**Phase 4d: Media Player**

Uses Astal's `mpris` service library.

Features:
- Album art display
- Track title, artist, album
- Progress bar with seek (scrub)
- Play/pause, next, previous, shuffle, repeat controls
- Player selector (if multiple MPRIS sources)

Waybar wiring:
```nix
mpris = {
  on-click = "ags request 'toggle:media'";
};
```

**Acceptance criteria (all Phase 4 widgets):**
- [ ] Each popup opens from Waybar click and closes on click-outside/Escape
- [ ] Singleton behavior: opening one closes others
- [ ] Correct monitor targeting on multi-monitor
- [ ] Styled with Stylix base16 colors
- [ ] Middle-click fallback actions work independently of AGS
- [ ] Data updates reactively (volume changes, network connects, device pairs)
- [ ] Audio mixer: per-app sliders appear for running audio apps
- [ ] Network: can connect to a new WiFi network end-to-end
- [ ] Bluetooth: can pair and connect a new device end-to-end
- [ ] Media: progress bar updates in real-time during playback

---

#### Phase 5: Dashboard Panel

**Scope:** Central control panel triggered by `$mod + A`.

**Files modified/created:**
- `/home/javels/nix-config/home/linux/ags/widgets/Dashboard.tsx` — new
- `/home/javels/nix-config/home/linux/ags/app.ts` — register window
- `/home/javels/nix-config/home/linux/hyprland.nix` — add `$mod + A` keybind

**Dashboard layout:**

```
┌─────────────────────────────────────┐
│  ┌──────┐                           │
│  │avatar│  username                 │
│  │      │  hostname                 │
│  └──────┘  uptime: 4d 12h          │
│─────────────────────────────────────│
│  Quick Settings                     │
│  [WiFi] [BT] [DND] [NightLight]    │
│  [Idle] [Screen Rec]               │
│─────────────────────────────────────│
│  System Stats                       │
│  CPU ████████░░ 72%   RAM ████░░ 42%│
│  GPU ██░░░░░░░░ 18%   Disk ██████ 60%│
│  Temp: CPU 62°C  GPU 45°C          │
│─────────────────────────────────────│
│  Power                              │
│  Profile: [Performance ▼]          │
│  Battery: 78% ⚡ Charging           │
│  Charge limit: 20-80%              │
│─────────────────────────────────────│
│  [Lock] [Logout] [Suspend]         │
│  [Reboot] [Shutdown]               │
└─────────────────────────────────────┘
```

**Features:**
- User profile card (avatar from `~/.face`, username, hostname, uptime)
- Quick settings toggles: WiFi, Bluetooth, DND mode, Night Light (`wlsunset`/`hyprsunset`), Idle inhibitor, Screen recording
- System stats: CPU, RAM, GPU (NVIDIA via `nvidia-smi`), disk usage, temperatures
- Power section: TLP profile display (via `tlp-stat -s`), battery status, charge thresholds
- Session actions: lock, logout, suspend, reboot, shutdown (replaces or supplements `wlogout`)

**Keybind** (`hyprland.nix`):
```nix
"$mod, A, exec, ags request 'toggle:dashboard'"
```

**Quick settings toggle implementation:**
- WiFi: `nmcli radio wifi on/off`
- Bluetooth: `bluetoothctl power on/off`
- DND: AGS internal flag, suppresses notification popups
- Night Light: `pkill wlsunset || wlsunset -t 4000 -T 6500`
- Idle inhibitor: toggle `hypridle` via `systemctl --user stop/start hypridle.service`
- Screen recording: start/stop `wl-screenrec` with PID tracking

**Acceptance criteria:**
- [ ] Dashboard opens/closes with `$mod + A`
- [ ] User avatar, hostname, uptime display correctly
- [ ] All quick settings toggles function and reflect current state
- [ ] System stats update reactively (CPU, RAM, GPU)
- [ ] TLP profile and battery info display correctly
- [ ] Session actions (lock, logout, etc.) work
- [ ] Dashboard closes when any session action is invoked
- [ ] Styled consistently with all other AGS widgets

---

#### Phase 6: Notification Center + OSD

**Scope:** Replace swaync with AGS notification daemon. Replace swayosd-server with AGS OSD.

**Files modified/created:**
- `/home/javels/nix-config/home/linux/ags/widgets/Notifications.tsx` — new
- `/home/javels/nix-config/home/linux/ags/widgets/OSD.tsx` — new
- `/home/javels/nix-config/home/linux/swaync.nix` — disable (`services.swaync.enable = false`)
- `/home/javels/nix-config/home/linux/hyprland.nix` — remove `swaync` from exec-once, remove `swayosd-server` from exec-once, update `$mod + N` keybind, replace `wpctl`/`brightnessctl` keybinds with AGS OSD commands

**Notification system:**

Uses Astal's `notifd` service library (implements `org.freedesktop.Notifications` D-Bus interface).

Features:
- Popup notifications (top-right, auto-dismiss after 5s)
- Notification center panel (slide from right, toggled by `$mod + N`)
- Notification history (in-memory, cleared on reboot)
- Per-notification actions (action buttons from the notification)
- DND mode integration (from dashboard quick settings)
- Notification grouping by app
- Clear all / clear individual
- Urgency-based styling (low/normal/critical)

**OSD overlays:**

Features:
- Volume change indicator (centered, auto-fade after 1.5s)
- Brightness change indicator (centered, auto-fade after 1.5s)
- Mic mute/unmute indicator
- Capslock/numlock indicator

Keybind changes in `hyprland.nix`:
```nix
# Volume — trigger AGS OSD instead of raw wpctl
"bindl, , XF86AudioRaiseVolume, exec, sh -c 'wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ && ags request osd:volume'"
"bindl, , XF86AudioLowerVolume, exec, sh -c 'wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && ags request osd:volume'"
"bindl, , XF86AudioMute, exec, sh -c 'wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && ags request osd:volume'"

# Brightness — trigger AGS OSD
"binde, , XF86MonBrightnessUp, exec, sh -c 'brightnessctl set 5%+ && ags request osd:brightness'"
"binde, , XF86MonBrightnessDown, exec, sh -c 'brightnessctl set 5%- && ags request osd:brightness'"
```

**Migration steps:**
1. Build and test AGS notification daemon alongside swaync (on a test session)
2. Verify D-Bus name acquisition works (`org.freedesktop.Notifications`)
3. Disable swaync: `services.swaync.enable = false`
4. Remove `swaync` from `exec-once` in hyprland.nix
5. Remove `swaynotificationcenter` from `home.packages` in hyprland.nix
6. Remove `swayosd-server` from `exec-once`
7. Update `$mod + N` to `ags request 'toggle:notifications'`
8. Rebuild and verify

**Acceptance criteria:**
- [ ] Application notifications appear as popups (top-right)
- [ ] Popups auto-dismiss after 5s (configurable)
- [ ] `$mod + N` opens notification center panel
- [ ] Notification history shows all received notifications
- [ ] Clear individual and clear all work
- [ ] DND mode suppresses popups but stores in history
- [ ] Critical notifications bypass DND
- [ ] Volume/brightness OSD appears on hardware key press
- [ ] OSD auto-fades after 1.5s
- [ ] No duplicate notifications (swaync fully removed)
- [ ] Notifications do not appear above hyprlock (security)

## System-Wide Impact

### Interaction Graph

1. Waybar `on-click` → spawns `ags request` subprocess → AGS `requestHandler` processes message → toggles corresponding window visibility
2. AGS notification daemon claims `org.freedesktop.Notifications` D-Bus name → all apps send notifications to AGS instead of swaync
3. Volume/brightness keybinds → `wpctl`/`brightnessctl` change value → `ags request osd:*` triggers OSD → AGS reads current value via WirePlumber/backlight service → renders overlay
4. Dashboard quick settings → shell commands (`nmcli`, `bluetoothctl`, etc.) → system state changes → AGS service libraries detect change via D-Bus signals → UI updates reactively

### Error Propagation

- **AGS crash**: Waybar continues rendering bar. Middle-click fallbacks work. Notifications are lost until AGS restarts. OSD stops showing. User must manually restart via `ags run` or re-login.
- **Astal service crash** (e.g., WirePlumber service): Individual widget may show stale data. Other widgets unaffected. AGS daemon stays alive.
- **Waybar crash**: AGS popups have no trigger mechanism (no bar to click). Dashboard still works via `$mod + A` keybind.

### State Lifecycle Risks

- **Notification state**: In-memory only. AGS restart = notifications lost. Acceptable per design decision.
- **Popup visibility state**: Boolean per window. No persistence needed. Clean on restart.
- **DND state**: In-memory. Lost on restart. Could persist to `~/.local/state/ags/dnd` if desired later.
- **No database or file-based state** that could become corrupted.

### Files Changed (Complete List)

| File | Action | Phase |
|---|---|---|
| `flake.nix` | Add `ags` and `astal` inputs | 2 |
| `home/linux/default.nix` | Add `./ags.nix` import | 2 |
| `home/linux/ags.nix` | New file — AGS home-manager config | 2 |
| `home/linux/ags/` | New directory — TypeScript widget source | 2-6 |
| `home/linux/waybar.nix` | Add modules (P1), update on-click handlers (P3-4) | 1, 3, 4 |
| `home/linux/hyprland.nix` | Add keybinds (P1), add `ags run` exec-once (P2), add dashboard bind (P5), update volume/brightness binds (P6), remove swaync/swayosd/applets (P6) | 1-6 |
| `home/linux/swaync.nix` | Disable (`enable = false`) | 6 |
| `home/linux/rofi.nix` | No changes needed | — |

## Dependencies & Prerequisites

1. **Phase 1 has no dependencies** — pure Waybar config changes
2. **Phase 2 requires** AGS and Astal flakes to resolve and build on NixOS 25.11
3. **Phase 3-5 require** Phase 2 scaffolding complete
4. **Phase 6 requires** Phase 3-5 popups stable (notification center should be last to avoid losing notifications during development)
5. **nvidia-smi** must be available for GPU module (already installed via nvidia.nix)
6. **wlsunset** or **hyprsunset** package needed for night light toggle (Phase 5)
7. **rofi-emoji** package needed for emoji picker keybind (Phase 1)

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| AGS flake doesn't build on NixOS 25.11 | Low | Blocks Phase 2+ | Pin to known-good commit. AGS has CI for NixOS. |
| Astal API changes between versions | Medium | Breaks widgets | Pin Astal flake input to specific commit, not `main`. |
| Stylix color bridge doesn't work | Low | Visual inconsistency | Fallback: hardcode Tokyo Night colors (breaks on theme change). |
| swaync removal loses notifications | Low | UX regression | Phase 6 is last. Test AGS notifications in parallel session first. |
| Performance: AGS + Waybar uses too much memory | Low | Resource pressure | Monitor with `htop`. AGS typically 50-150MB. Acceptable on 32GB system. |
| Multi-monitor popup positioning wrong | Medium | UX issue | Test with external monitor during Phase 3 (calendar). Fix before Phase 4. |

## Future Considerations

**Revisit Quickshell (QML/Qt6) in late 2026.** If it reaches stable and the theming story improves, it could replace both Waybar and AGS as a unified shell. (see brainstorm: Future Consideration)

**Potential Phase 7 additions (out of scope for now):**
- App launcher widget (replace rofi with AGS launcher)
- Clipboard manager widget (replace cliphist+rofi with AGS)
- Screen recording indicator in bar
- Cava audio visualizer widget
- System update notifier with one-click update

## Sources & References

### Origin

- **Brainstorm document:** [docs/brainstorms/2026-03-02-hyprpanel-parity-brainstorm.md](docs/brainstorms/2026-03-02-hyprpanel-parity-brainstorm.md) — Key decisions carried forward: hybrid Waybar+AGS architecture, AGS v3/Astal, incremental rollout, Quickshell revisit in late 2026.

### Internal References

- Waybar config: `home/linux/waybar.nix`
- Hyprland config: `home/linux/hyprland.nix`
- SwayNC config: `home/linux/swaync.nix`
- Flake inputs: `flake.nix:4-29`
- Stylix config: `modules/nixos/stylix.nix`
- Wallpaper module (pattern reference): `home/linux/wallpaper.nix`
- Linux HM imports: `home/linux/default.nix`
- Power/TLP config: `modules/nixos/power.nix`
- Daily driver rice plan: `docs/plans/2026-03-02-feat-daily-driver-rice-plan.md`

### External References

- AGS v3 repository: https://github.com/Aylur/ags
- Astal framework: https://github.com/Aylur/astal
- AGS NixOS guide: https://aylur.github.io/ags/guide/nix.html
- HyprPanel (reference implementation): https://github.com/Jas-SinghFSU/HyprPanel
- Astal service libraries: https://aylur.github.io/astal/
- ags2-shell (NixOS reference config): https://github.com/TheWolfStreet/ags2-shell
- matshell (Material Design reference): https://github.com/Neurarian/matshell
