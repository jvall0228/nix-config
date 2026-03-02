---
title: "feat: NixOS Daily Driver + Tokyo Night Rice"
type: feat
status: active
date: 2026-03-02
origin: docs/brainstorms/2026-03-02-daily-driver-rice-brainstorm.md
---

# feat: NixOS Daily Driver + Tokyo Night Rice

## Overview

Transform the current bare-bones Hyprland NixOS setup into a fully daily-drivable workstation with a cohesive Tokyo Night rice. The system should support development, browsing, media, communication, document editing, and file management — all themed via Stylix from a single source of truth.

The foundation is solid (Hyprland, PipeWire, NVIDIA, Secure Boot, LUKS), but every user-facing tool runs on stock defaults with no theming, missing keybindings, no lock screen, and no communication apps (see brainstorm: `docs/brainstorms/2026-03-02-daily-driver-rice-brainstorm.md`).

## Problem Statement / Motivation

The current setup boots to a functional but unusable desktop: no lock screen (security risk), no media/volume keys, only 5 workspaces bound, no notifications center, no app launcher worth using, no file manager, no communication apps, and zero theming. Every session requires manual workarounds. This blocks daily-driver usage.

## Proposed Solution

A phased implementation across four scopes, with Stylix integrated first as the theming foundation:

1. **Stylix + Foundation** — Flake input, Tokyo Night scheme, fonts, wallpaper
2. **Daily-Driver Essentials** — Lock screen, keybindings, apps, system tray, portals
3. **Desktop Shell Rice** — Waybar, rofi, SwayNC, animations, GTK/QT theming
4. **Terminal + Editor Rice** — Kitty, tmux, starship, fastfetch, neovim LSPs

## Technical Approach

### Architecture

All configuration managed through home-manager where possible, following existing repo conventions (see brainstorm: architecture notes):

- Desktop/GUI configs → `home/linux/` (new leaf modules)
- Terminal/shell configs → `home/common/` (cross-platform)
- System services → `modules/nixos/` (greetd, PAM, portals)
- Stylix → `modules/nixos/stylix.nix` (system-level, consistent with NixOS-only module pattern)

Every new module is a flat leaf node with `{ pkgs, ... }:` or `{ ... }:` signature (no `mkOption`/`mkEnableOption`), imported into the nearest aggregator.

### Decisions Made During Planning

These resolve open questions from the brainstorm and gaps identified during SpecFlow analysis:

| Decision | Resolution | Rationale |
|----------|-----------|-----------|
| Wallpaper authority | Stylix sets `stylix.image` for greetd/theming; swww in `exec-once` loads same path at runtime | Stylix needs an image for greetd + GTK theming; swww handles runtime transitions. waypaper overrides at runtime only. |
| Lock keybind | `$mod SHIFT, L` → `hyprlock` | `$mod, L` is already bound to `movefocus, r` (vim-style HJKL navigation). Shift modifier is intuitive for "lock". |
| `$mod, M` (hard exit) | Replace with `exec, wlogout` | Current binding hard-exits Hyprland without confirmation — data loss risk. wlogout provides lock/logout/suspend/reboot/shutdown options. |
| Polkit agent | Keep existing `polkit-kde-agent-1`; exec binary directly in `exec-once` | Already installed in `modules/nixos/hyprland.nix`. Must exec the binary path directly — no systemd user unit exists for it. |
| hypridle timeouts | 5min → lock, 15min → suspend (on battery); 10min → lock, 30min → suspend (on AC) | Sensible defaults for laptop. Single config initially (no AC/battery split — simplify). 5min lock, 15min suspend. |
| Syncthing | Home-manager `services.syncthing.enable`; open firewall ports 22000, 21027 | User-level service is simpler. LAN sync requires firewall rules. |
| Nautilus + gvfs | Enable `services.gvfs.enable = true` | Without gvfs, Nautilus lacks trash, thumbnails, and mount support. One-line addition. |
| Neovim Mason | Disable Mason auto-install in LazyVim config | LSPs installed via Nix `extraPackages`. Mason would create duplicate/conflicting binaries. |
| QT theming | Add `qt.enable = true` + `qt.platformTheme.name = "kvantum"` in home-manager | Stylix auto-themes Kvantum. QT apps need explicit platform config. |
| cliphist watcher | Add `wl-paste --type text --watch cliphist store` and `wl-paste --type image --watch cliphist store` to `exec-once` | cliphist is useless without the watcher process. |
| Screenshot keybinds | `Print` → region select → clipboard; `$mod, Print` → region select → save to `~/Pictures/Screenshots/`; `$mod SHIFT, Print` → fullscreen → save. All commands wrapped in `sh -c` for shell features. | Three-bind pattern covers common needs. swappy deferred to extras. Hyprland exec doesn't invoke a shell — pipes, `$(...)`, and `&&` require explicit `sh -c` wrapping. |
| Hyprland shell wrapping | All `exec-once` and `bind` entries using pipes, `$(...)`, or `&&` must be wrapped in `sh -c '...'` | Hyprland dispatches commands directly without a shell. Pipes and subshells silently fail without wrapping. |
| wlogout config method | Use `home.packages` + `xdg.configFile` (no `programs.wlogout` HM module exists) | wlogout has no home-manager module. Config must be deployed as a file. |
| HiDPI env vars | Omit `GDK_SCALE=2` initially — test without it first | Hyprland's `monitor = ",preferred,auto,2"` already scales native Wayland apps. `GDK_SCALE=2` may double-scale GTK3 apps. Add only if apps render too small. |
| Papirus icon theme | Install `pkgs.papirus-icon-theme` in `home/linux/desktop.nix` | rofi references `Papirus-Dark` but the theme package was missing from the plan. |
| Fastfetch autorun | Manual invocation only (alias `ff`) | Auto-run adds latency to every terminal open. |
| wlsunset | Auto-start with hardcoded coordinates (user's approximate location) | Set-and-forget. User can adjust lat/long in config. |
| Plymouth | Defer to Phase 5 (extras) | Requires vendoring a theme or finding a compatible nixpkgs package. Low priority vs. functional gaps. |
| Waybar tray module | Include `tray` module | Required for nm-applet and blueman-applet visibility. |

### Implementation Phases

#### Phase 1: Stylix + Foundation

**Goal:** Establish theming foundation. All subsequent phases inherit colors automatically.

**Files to create:**
- `modules/nixos/stylix.nix` — Stylix configuration (scheme, fonts, wallpaper, targets)

**Files to modify:**
- `flake.nix` — Add Stylix flake input + `stylix.nixosModules.stylix` to modules list
- `home/linux/desktop.nix` — Replace `nerd-fonts.symbols-only` with full font packages

**`flake.nix` changes:**

```nix
# In inputs:
stylix = {
  url = "github:nix-community/stylix";
  inputs.nixpkgs.follows = "nixpkgs";
};

# In outputs destructure: add stylix
# In nixosConfigurations.thinkpad.modules: add
stylix.nixosModules.stylix
./modules/nixos/stylix.nix
```

**`modules/nixos/stylix.nix`:**

```nix
{ pkgs, ... }:
{
  stylix = {
    enable = true;
    autoEnable = true;
    # NOTE: Verify exact filename in nixpkgs 25.11 — may be tokyo-night-dark.yaml
    # or tokyo-night-terminal-dark.yaml. Check with:
    #   ls $(nix build nixpkgs#base16-schemes --print-out-paths)/share/themes/ | grep tokyo
    base16Scheme = "${pkgs.base16-schemes}/share/themes/tokyo-night-dark.yaml";
    # Wallpaper must exist at this path relative to this file, or use pkgs.fetchurl/absolute path.
    # Store in repo: assets/wallpaper.png, then reference as ../../assets/wallpaper.png
    image = ../../assets/wallpaper.png;
    polarity = "dark";

    fonts = {
      monospace = {
        package = pkgs.nerd-fonts.jetbrains-mono;
        # NOTE: Verify exact name with `fc-list | grep JetBrains` after install.
        # May be "JetBrainsMono Nerd Font" or "JetBrainsMono Nerd Font Mono".
        name = "JetBrainsMono Nerd Font";
      };
      sansSerif = {
        package = pkgs.noto-fonts;
        name = "Noto Sans";
      };
      serif = {
        package = pkgs.noto-fonts;
        name = "Noto Serif";
      };
      emoji = {
        package = pkgs.noto-fonts-color-emoji;
        name = "Noto Color Emoji";
      };
      sizes = {
        terminal = 14;
        applications = 12;
        desktop = 11;
        popups = 12;
      };
    };

    cursor = {
      package = pkgs.bibata-cursors;
      name = "Bibata-Modern-Classic";
      size = 24;
    };

    targets.greetd.enable = true;
  };
}
```

**`home/linux/desktop.nix` font changes:**

```nix
# Replace nerd-fonts.symbols-only with:
nerd-fonts.jetbrains-mono
noto-fonts-color-emoji
noto-fonts-cjk-sans
font-awesome
```

**Acceptance criteria:**
- [ ] `nix flake check` passes with Stylix input
- [ ] `nixos-rebuild dry-build` succeeds
- [ ] `bash apps/build-switch` applies successfully
- [ ] Verify Stylix HM integration is wired (if not automatic, add `stylix.homeManagerIntegration.enable = true` in flake.nix HM config)
- [ ] Kitty terminal shows Tokyo Night colors (Stylix auto-targets kitty)
- [ ] GTK apps show dark theme
- [ ] Cursor theme applied
- [ ] JetBrains Mono Nerd Font renders in terminal — verify name with `fc-list | grep JetBrains`
- [ ] Verify base16 scheme file exists: `ls $(nix build nixpkgs#base16-schemes --print-out-paths)/share/themes/ | grep tokyo`

**Validation:** Dry-build first, then switch. Visual check: open kitty + Firefox, verify dark theme + correct fonts.

---

#### Phase 2: Daily-Driver Essentials

**Goal:** Make the system functional for daily use — lock screen, keybindings, apps, system tray.

**Files to create:**
- `home/linux/hyprlock.nix` — Lock screen + idle daemon configuration
- `home/linux/wlogout.nix` — Power menu configuration
- `modules/nixos/greetd.nix` — Login greeter service

**Files to modify:**
- `flake.nix` — Add `modules/nixos/greetd.nix` to modules list
- `home/linux/default.nix` — Add imports for `hyprlock.nix`, `wlogout.nix`
- `home/linux/hyprland.nix` — XF86 keybinds, workspaces 6-9, env vars, exec-once entries, replace `$mod M` with wlogout
- `home/linux/desktop.nix` — Add communication apps, media player, file manager, utilities
- `modules/nixos/hyprland.nix` — Add PAM service for hyprlock, `xdg-desktop-portal-gtk`, gvfs
- `modules/nixos/core.nix` — Add Syncthing firewall rules (if not handled by home-manager)

**`home/linux/hyprland.nix` key changes:**

```nix
# Replace wofi, mako in home.packages with:
rofi-wayland
swaynotificationcenter
hyprlock
hypridle
wlogout
cliphist
wl-clipboard
grim
slurp
swww
brightnessctl
playerctl
swayosd
nm-applet
blueman
nautilus
wl-screenrec
hyprpicker

# exec-once additions:
# NOTE: Hyprland exec-once does NOT invoke a shell. Commands with &&, |, or $()
# must be wrapped in `sh -c '...'`. Simple commands are fine without wrapping.
"waybar"
"swaync"
"swww-daemon"                                              # start daemon first
"sh -c 'sleep 1; swww img /path/to/wallpaper.png'"        # delay to let daemon init
# DO NOT add "hyprlock" here — it would immediately lock the session on login.
# hypridle handles invoking hyprlock on idle timeout.
"nm-applet --indicator"
"blueman-applet"
"/run/current-system/sw/bin/polkit-kde-agent-1"            # exec binary directly (no systemd unit exists)
"wl-paste --type text --watch cliphist store"
"wl-paste --type image --watch cliphist store"
"swayosd-server"

# New keybinds:
# NOTE: All commands using pipes, $(), or && MUST use `sh -c '...'` wrapping.
"$mod SHIFT, L, exec, hyprlock"                           # manual lock
"$mod, M, exec, wlogout"                                  # power menu (replaces hard exit)
"$mod, D, exec, rofi -show drun"                          # app launcher
"$mod, V, exec, sh -c 'cliphist list | rofi -dmenu | cliphist decode | wl-copy'"  # clipboard
"$mod, N, exec, swaync-client -t -sw"                     # notification center toggle
", Print, exec, sh -c 'grim -g \"$(slurp)\" - | wl-copy'"                         # screenshot → clipboard
"$mod, Print, exec, sh -c 'grim -g \"$(slurp)\" ~/Pictures/Screenshots/$(date +%Y%m%d-%H%M%S).png'"  # screenshot → file
"$mod SHIFT, Print, exec, sh -c 'grim ~/Pictures/Screenshots/$(date +%Y%m%d-%H%M%S).png'"            # fullscreen → file

# XF86 keybinds:
", XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
", XF86AudioMicMute, exec, wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"
", XF86MonBrightnessUp, exec, brightnessctl set 5%+"
", XF86MonBrightnessDown, exec, brightnessctl set 5%-"
", XF86AudioPlay, exec, playerctl play-pause"
", XF86AudioNext, exec, playerctl next"
", XF86AudioPrev, exec, playerctl previous"

# Workspaces 6-9 (add to existing 1-5):
"$mod, 6, workspace, 6"  # through 9
"$mod SHIFT, 6, movetoworkspace, 6"  # through 9

# Environment variables:
"ELECTRON_OZONE_PLATFORM_HINT,auto"
"QT_QPA_PLATFORM,wayland"
"QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
# DO NOT set GDK_SCALE=2 — Hyprland's monitor scale (auto,2) already handles this.
# Setting GDK_SCALE=2 will double-scale GTK3 apps. Only add if specific apps render too small.
```

**`home/linux/hyprlock.nix`:**

```nix
{ ... }:
{
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        grace = 5;
        hide_cursor = true;
      };
      background = [{
        monitor = "";
        path = "screenshot";
        blur_passes = 3;
        blur_size = 8;
      }];
      input-field = [{
        monitor = "";
        size = "300, 50";
        outline_thickness = 3;
        fade_on_empty = true;
        placeholder_text = "Password...";
        fail_text = "Authentication failed";
        position = "0, -20";
        halign = "center";
        valign = "center";
      }];
    };
  };

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      listener = [
        { timeout = 300; on-timeout = "hyprlock"; }          # 5min → lock
        { timeout = 900; on-timeout = "systemctl suspend"; }  # 15min → suspend
      ];
    };
  };
}
```

**`modules/nixos/hyprland.nix` additions:**

```nix
# Enable hyprlock at system level — this auto-creates the PAM service entry
# (/etc/pam.d/hyprlock) needed for lock screen authentication.
# Without this, hyprlock renders but auth always fails → permanent lockout.
programs.hyprlock.enable = true;

# Add GTK portal (required for file dialogs in Firefox, Electron apps, Nautilus):
xdg.portal.extraPortals = [
  pkgs.xdg-desktop-portal-hyprland
  pkgs.xdg-desktop-portal-gtk
];

# Enable gvfs for Nautilus (trash, thumbnails, mount support):
services.gvfs.enable = true;
```

**`modules/nixos/core.nix` additions (Syncthing firewall):**

```nix
# Syncthing LAN sync — home-manager cannot modify system firewall
networking.firewall.allowedTCPPorts = [ 22000 ];
networking.firewall.allowedUDPPorts = [ 22000 21027 ];
```

**`home/linux/desktop.nix` app additions:**

```nix
# Communication:
discord
slack
telegram-desktop
obsidian

# Media:
mpv

# Icons (required by rofi icon-theme = "Papirus-Dark"):
papirus-icon-theme

# Utilities (already have some via hyprland.nix packages):
nautilus
```

**`modules/nixos/greetd.nix`:**

```nix
{ pkgs, ... }:
{
  # NOTE: Verify regreet availability in nixpkgs 25.11 before implementing.
  # programs.regreet.enable automatically configures greetd with the correct
  # session command, user, and Hyprland cage wrapper.
  programs.regreet.enable = true;

  # Ensure a TTY getty remains available as fallback (Ctrl+Alt+F2)
  # in case regreet fails to start. NixOS keeps getty@tty2 by default,
  # but verify after enabling greetd.
}
```

**`home/linux/wlogout.nix`:**

```nix
{ pkgs, ... }:
{
  # No programs.wlogout module exists in home-manager.
  # Install package + deploy config manually.
  home.packages = [ pkgs.wlogout ];

  xdg.configFile."wlogout/layout" = {
    text = ''
      {
        "label" : "lock",
        "action" : "hyprlock",
        "text" : "Lock",
        "keybind" : "l"
      }
      {
        "label" : "logout",
        "action" : "hyprctl dispatch exit",
        "text" : "Logout",
        "keybind" : "e"
      }
      {
        "label" : "suspend",
        "action" : "systemctl suspend",
        "text" : "Suspend",
        "keybind" : "s"
      }
      {
        "label" : "reboot",
        "action" : "systemctl reboot",
        "text" : "Reboot",
        "keybind" : "r"
      }
      {
        "label" : "shutdown",
        "action" : "systemctl poweroff",
        "text" : "Shutdown",
        "keybind" : "p"
      }
    '';
  };
  # Stylix/GTK theming will apply to wlogout's GTK window automatically.
}
```

**Acceptance criteria:**
- [ ] hyprlock renders and authenticates successfully (test manually before enabling hypridle)
- [ ] hypridle locks screen after 5min idle
- [ ] wlogout opens with `$mod+M` and all actions (lock/logout/suspend/reboot/shutdown) work
- [ ] Volume/brightness/media XF86 keys work with hardware buttons
- [ ] swayosd shows OSD feedback for volume/brightness changes
- [ ] Workspaces 1-9 switch and move-to-workspace work
- [ ] rofi launches with `$mod+D` and opens applications
- [ ] cliphist accumulates clipboard history and `$mod+V` retrieves it via rofi
- [ ] SwayNC notification center toggles with `$mod+N`
- [ ] Screenshots work (all three keybinds)
- [ ] nm-applet and blueman-applet visible in Waybar tray
- [ ] Discord, Slack, Telegram render correctly under Wayland (no blank windows)
- [ ] Nautilus opens and can browse files, use trash
- [ ] greetd+regreet shows themed login screen (test on separate TTY first)
- [ ] `$mod+M` no longer hard-exits Hyprland

**Validation:**
1. Dry-build after each sub-change
2. Test hyprlock manually (`hyprlock` from terminal) BEFORE enabling hypridle
3. Test greetd on a separate TTY or confirm Ctrl+Alt+F2 fallback works
4. Test all XF86 keys with hardware buttons
5. Verify Electron apps render correctly

---

#### Phase 3: Desktop Shell Rice

**Goal:** Polish the desktop shell — waybar, rofi theming, SwayNC styling, animations.

**Files to create:**
- `home/linux/waybar.nix` — Full waybar configuration
- `home/linux/rofi.nix` — rofi-wayland configuration
- `home/linux/swaync.nix` — SwayNC notification center configuration

**Files to modify:**
- `home/linux/default.nix` — Add imports for `waybar.nix`, `rofi.nix`, `swaync.nix`
- `home/linux/hyprland.nix` — Add animations block, border colors (Stylix handles colors but animations need manual config)

**`home/linux/waybar.nix`:**

```nix
{ ... }:
{
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 36;
        modules-left = [ "hyprland/workspaces" "hyprland/window" ];
        modules-center = [ "clock" ];
        modules-right = [
          "mpris"
          "pulseaudio"
          "network"
          "bluetooth"
          "battery"
          "cpu"
          "tray"  # Required for nm-applet, blueman-applet
        ];

        "hyprland/workspaces" = {
          format = "{icon}";
          on-click = "activate";
        };
        clock = {
          format = "{:%H:%M  %a %b %d}";
          tooltip-format = "<tt>{calendar}</tt>";
        };
        battery = {
          format = "{icon}  {capacity}%";
          format-icons = [ "" "" "" "" "" ];
          states = { warning = 30; critical = 15; };
        };
        cpu = { format = "  {usage}%"; interval = 5; };
        pulseaudio = {
          format = "{icon}  {volume}%";
          format-muted = "  muted";
          format-icons.default = [ "" "" "" ];
          on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        };
        network = {
          format-wifi = "  {essid}";
          format-ethernet = "  {ifname}";
          format-disconnected = "  disconnected";
        };
        bluetooth = {
          format = " {status}";
          on-click = "blueman-manager";
        };
        mpris = {
          format = "{player_icon}  {title}";
          player-icons.default = "";
        };
        tray = { spacing = 10; };
      };
    };
    # NOTE: Stylix auto-generates CSS with font-family and colors.
    # Do NOT override font-family here — it conflicts with Stylix's generated CSS.
    # Only add layout/spacing styles that Stylix doesn't cover.
    style = ''
      * {
        border-radius: 8px;
      }
      window#waybar {
        background: transparent;
      }
      #workspaces button.active {
        border-bottom: 2px solid @base0D;
      }
    '';
  };
}
```

**`home/linux/rofi.nix`:**

```nix
{ pkgs, ... }:
{
  programs.rofi = {
    enable = true;
    package = pkgs.rofi-wayland;
    terminal = "kitty";
    extraConfig = {
      show-icons = true;
      icon-theme = "Papirus-Dark";
      display-drun = "Apps";
      drun-display-format = "{name}";
    };
  };
}
```

**`home/linux/swaync.nix`:**

```nix
{ ... }:
{
  services.swaync = {
    enable = true;
    settings = {
      positionX = "right";
      positionY = "top";
      control-center-width = 400;
      notification-window-width = 400;
      notification-icon-size = 48;
      fit-to-screen = true;
      hide-on-clear = true;
    };
    # Stylix auto-themes SwayNC via GTK; additional CSS can go in style
  };
}
```

**Hyprland animations block (add to `home/linux/hyprland.nix`):**

**IMPORTANT:** When refactoring `hyprland.nix`, preserve existing NVIDIA-critical settings:
- `render.explicit_sync = 2` and `render.explicit_sync_kms = 2` — removing these causes flickering on NVIDIA.

```nix
animations = {
  enabled = true;
  bezier = [
    "ease, 0.25, 0.1, 0.25, 1.0"
    "easeOut, 0.0, 0.0, 0.2, 1.0"
  ];
  animation = [
    "windows, 1, 4, ease, slide"
    "windowsOut, 1, 4, easeOut, slide"
    "fade, 1, 3, ease"
    "workspaces, 1, 3, ease, slide"
  ];
};
```

**Acceptance criteria:**
- [ ] Waybar renders at top with all modules functional
- [ ] Waybar tray shows nm-applet and blueman icons
- [ ] Waybar clock, battery, CPU, volume, network modules display data
- [ ] rofi launches with Tokyo Night theme applied (Stylix)
- [ ] SwayNC popups appear with urgency-differentiated styling
- [ ] SwayNC notification center toggles from Waybar click and keybind
- [ ] Hyprland animations render smoothly (no tearing on NVIDIA)
- [ ] GTK apps (Nautilus, Firefox) show Papirus Dark icons + Tokyo Night colors

**Validation:** Visual inspection of each component. If animations cause tearing, reduce durations or disable specific types.

---

#### Phase 4: Terminal + Editor Rice

**Goal:** Port terminal tooling from macOS dotfiles, set up neovim LSPs.

**Files to create:**
- `home/common/kitty.nix` — Kitty terminal configuration
- `home/common/tmux.nix` — Tmux configuration (replaces raw package in dev-tools.nix)
- `home/common/fastfetch.nix` — System info display
- `home/linux/starship.nix` — Platform-specific starship config (NixOS icon)

**Files to modify:**
- `home/default.nix` — Add imports for `kitty.nix`, `tmux.nix`, `fastfetch.nix`
- `home/linux/default.nix` — Add import for `starship.nix`
- `home/common/shell.nix` — Keep `programs.starship.enable = true`; settings move to platform-specific files
- `home/common/dev-tools.nix` — Remove bare `tmux` package
- `home/common/neovim.nix` — Add `extraPackages` for LSP servers

**`home/common/kitty.nix`:**

```nix
{ ... }:
{
  programs.kitty = {
    enable = true;
    settings = {
      # Stylix handles colors and font automatically
      font_size = 14;
      window_padding_width = 8;
      confirm_os_window_close = 0;
      enable_audio_bell = false;
      scrollback_lines = 10000;
    };
  };
}
```

**`home/common/tmux.nix`:**

```nix
{ pkgs, ... }:
{
  programs.tmux = {
    enable = true;
    terminal = "tmux-256color";
    shell = "${pkgs.bash}/bin/bash";
    keyMode = "vi";
    baseIndex = 1;
    escapeTime = 0;
    historyLimit = 10000;
    mouse = true;
    plugins = with pkgs.tmuxPlugins; [
      sensible
      vim-tmux-navigator
      tokyo-night-tmux
    ];
    extraConfig = ''
      set -g status-position top
      set -ag terminal-overrides ",xterm-256color:RGB"
    '';
  };
}
```

**`home/common/neovim.nix` additions:**

```nix
{ pkgs, ... }:
{
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    extraPackages = with pkgs; [
      # LSP servers
      lua-language-server
      pyright
      rust-analyzer
      typescript-language-server
      nil  # Nix LSP

      # Formatters / tools
      stylua
      black
      nodePackages.prettier
    ];
  };
}
```

**`home/linux/starship.nix`:**

```nix
{ ... }:
{
  programs.starship.settings = {
    format = "$os$directory$git_branch$git_status$character";
    os = {
      disabled = false;
      symbols.NixOS = " ";
    };
    directory.style = "blue bold";
    git_branch.style = "purple";
    character = {
      success_symbol = "[❯](blue)";
      error_symbol = "[❯](red)";
    };
  };
}
```

**`home/common/fastfetch.nix`:**

```nix
{ pkgs, ... }:
{
  home.packages = [ pkgs.fastfetch ];
  # Config managed via XDG config file if needed, or use default NixOS detection
}
```

**Acceptance criteria:**
- [ ] Kitty opens with Tokyo Night colors + JetBrains Mono (Stylix-managed)
- [ ] Tmux starts with top status bar, Tokyo Night theme, vi keybindings
- [ ] Starship prompt shows NixOS icon + Tokyo Night blue-gradient style
- [ ] Fastfetch displays NixOS logo and system info when invoked (`fastfetch`)
- [ ] Neovim launches with LSP servers available (`:LspInfo` shows connected servers)
- [ ] No Mason auto-install conflicts (verify `~/.local/share/nvim/mason/` is empty or disabled)
- [ ] `tmux` no longer appears as a bare package in `dev-tools.nix`

---

#### Phase 5: Extras (Deferred / Low Priority)

These are nice-to-haves from the brainstorm that can be implemented after the core rice is stable:

- [ ] Plymouth boot splash (Tokyo Night theme — requires finding/vendoring a theme package)
- [ ] hyprexpo plugin (workspace overview — requires matching Hyprland version)
- [ ] waypaper (GUI wallpaper picker — uses swww backend)
- [ ] wlsunset (night light — hardcode approximate coordinates)
- [ ] swappy (screenshot annotation tool)
- [ ] wl-screenrec keybind (screen recording)

## System-Wide Impact

### Interaction Graph

```
Stylix (system-level)
  ├── Generates: GTK theme, cursor theme, kitty colors, waybar CSS vars, hyprlock colors
  ├── Sets: stylix.image → used by greetd/regreet background
  └── Propagates via: home-manager targets (autoEnable = true)

Hyprland exec-once
  ├── waybar → reads Stylix CSS → renders bar
  ├── swaync → inherits GTK theme → renders notifications
  ├── swww-daemon → loads wallpaper at runtime
  ├── hypridle → monitors idle → invokes hyprlock → invokes suspend
  ├── nm-applet → renders in waybar tray
  ├── blueman-applet → renders in waybar tray
  ├── polkit-kde-agent-1 → handles privilege prompts
  ├── cliphist watchers (text + image) → stores clipboard history
  └── swayosd-server → renders OSD popups
```

### Error & Failure Propagation

| Failure | Impact | Recovery |
|---------|--------|----------|
| Stylix eval error | Entire build fails (system-level module) | `nixos-rebuild dry-build` catches this before apply |
| hyprlock PAM missing | Lock screen renders but auth always fails → permanent lockout | SSH in or TTY switch (Ctrl+Alt+F2), fix config, rebuild |
| greetd misconfigured | Boot to black screen / crash loop | TTY fallback (Ctrl+Alt+F2), `sudo nixos-rebuild switch --rollback` |
| NVIDIA + hyprlock blank | Lock screen blank → can't authenticate | Set `HYPRLOCK_RENDERER=gl` env var, rebuild |
| swww crash | No wallpaper (black background) | Non-critical, restart swww-daemon |
| Waybar crash | No status bar | Non-critical, restart waybar |

### State Lifecycle Risks

- **Lanzaboote generation limit (10):** Iterative rebuilds during ricing can exhaust bootloader entries. Run `bash apps/clean` between rebuild batches.
- **Auto-upgrade at 04:00:** Uncommitted changes will be overwritten. Commit and push before end of session.
- **hyprlock + hypridle ordering:** If hypridle triggers before hyprlock is verified working, the machine may become locked with a broken lock screen. Always test `hyprlock` manually first.

## Acceptance Criteria

### Functional Requirements

- [ ] Boot → greetd/regreet → login → Hyprland session with all autostart services running
- [ ] Lock screen works (manual keybind + idle timeout + lid close)
- [ ] All XF86 media/volume/brightness keys functional
- [ ] App launcher (rofi), clipboard manager (cliphist), notification center (SwayNC) functional
- [ ] Communication apps (Discord, Slack, Telegram) render correctly on Wayland
- [ ] File manager (Nautilus) with trash/mount support (gvfs)
- [ ] 9 workspaces bound and navigable
- [ ] wlogout power menu replaces hard exit

### Non-Functional Requirements

- [ ] Cohesive Tokyo Night theming across all visible UI surfaces
- [ ] No font rendering issues (JetBrains Mono NF everywhere)
- [ ] No NVIDIA-related visual glitches (tearing, blank screens)
- [ ] Smooth animations (or gracefully degraded if NVIDIA conflicts)
- [ ] HiDPI renders correctly at 2x scale

### Quality Gates

- [ ] `nixos-rebuild dry-build` succeeds after each phase
- [ ] System rollback tested before greetd activation
- [ ] hyprlock tested manually before hypridle activation
- [ ] All keybindings tested with hardware keys

## Dependencies & Prerequisites

1. **Stylix flake must build with NixOS 25.11** — verify compatibility before starting
2. **Tokyo Night wallpaper** — source or create a wallpaper image before Phase 1
3. **LazyVim Lua config** — must exist (from shared-dotfiles) before neovim hybrid setup
4. **macOS dotfiles reference** — for porting kitty, tmux, starship configs

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Stylix incompatible with NixOS 25.11 | Low | High (blocks entire plan) | Check Stylix repo for 25.11 branch/tag before starting |
| NVIDIA + hyprlock blank screen | Medium | High (lockout risk) | Test hyprlock in terminal first; have `HYPRLOCK_RENDERER=gl` ready |
| greetd boot loop | Medium | High (can't login) | Test on separate TTY; keep TTY getty enabled; know rollback command |
| Exhaust 10 bootloader generations | Medium | Medium (can't boot old configs) | Run `bash apps/clean` between phases |
| Stylix conflicts with manual configs | Low | Low (override with mkForce) | Use `stylix.targets.<name>.enable = false` for specific opt-outs |
| Electron apps blank on Wayland | Low | Medium (apps unusable) | `ELECTRON_OZONE_PLATFORM_HINT=auto` env var; fallback to XWayland |

## File Change Summary

### New Files (11)

| File | Purpose | Wired Into |
|------|---------|------------|
| `modules/nixos/stylix.nix` | Stylix theme config | `flake.nix` modules list |
| `modules/nixos/greetd.nix` | Login greeter | `flake.nix` modules list |
| `home/linux/waybar.nix` | Status bar | `home/linux/default.nix` |
| `home/linux/rofi.nix` | App launcher | `home/linux/default.nix` |
| `home/linux/swaync.nix` | Notification center | `home/linux/default.nix` |
| `home/linux/hyprlock.nix` | Lock screen + idle | `home/linux/default.nix` |
| `home/linux/wlogout.nix` | Power menu | `home/linux/default.nix` |
| `home/linux/starship.nix` | NixOS starship config | `home/linux/default.nix` |
| `home/common/kitty.nix` | Terminal config | `home/default.nix` |
| `home/common/tmux.nix` | Tmux config | `home/default.nix` |
| `home/common/fastfetch.nix` | System info | `home/default.nix` |

### Modified Files (9)

| File | Changes |
|------|---------|
| `flake.nix` | Add Stylix input + modules |
| `home/linux/default.nix` | Add 7 new imports |
| `home/default.nix` | Add 3 new imports |
| `home/linux/hyprland.nix` | Replace wofi/mako; add keybinds, exec-once, animations, env vars |
| `home/linux/desktop.nix` | Full font packages + communication/media/utility apps |
| `modules/nixos/hyprland.nix` | PAM for hyprlock, xdg-desktop-portal-gtk, gvfs |
| `modules/nixos/core.nix` | Syncthing firewall rules (if needed) |
| `home/common/neovim.nix` | Add LSP extraPackages |
| `home/common/dev-tools.nix` | Remove bare tmux package |

## Sources & References

### Origin

- **Brainstorm document:** [docs/brainstorms/2026-03-02-daily-driver-rice-brainstorm.md](docs/brainstorms/2026-03-02-daily-driver-rice-brainstorm.md) — Key decisions carried forward: Stylix for unified theming, rofi-wayland replaces wofi, SwayNC replaces mako, JetBrains Mono Nerd Font, greetd+regreet login manager, hybrid neovim approach.

### Internal References

- `flake.nix` — Flake input pattern (follows nixpkgs)
- `modules/nixos/hyprland.nix` — Existing polkit + portal config
- `home/linux/hyprland.nix` — Current Hyprland settings baseline
- `home/linux/desktop.nix` — Current font/app packages
- `home/common/dev-tools.nix` — Current tmux package location

### External References

- [Stylix (nix-community)](https://github.com/nix-community/stylix) — Theming framework
- [Frost-Phoenix/nixos-config](https://github.com/Frost-Phoenix/nixos-config) — Reference Hyprland rice
- [anotherhadi/nixy](https://github.com/anotherhadi/nixy) — Stylix-driven theming reference
- [Hyprland Wiki - Useful Utilities](https://wiki.hypr.land/Useful-Utilities/Must-have/) — Official tool recommendations

## Review Feedback Applied

This plan was reviewed by Codex (GPT-5.2) and Gemini CLI. The following fixes were applied based on their feedback:

| Fix | Source | Severity |
|-----|--------|----------|
| Wrap all Hyprland `exec`/`bind` commands using `\|`, `&&`, `$(...)` in `sh -c '...'` | Both | Blocker |
| Remove `hyprlock` from `exec-once` (would lock session immediately on login) | Codex | Blocker |
| Replace `systemctl --user start polkit-kde-agent-1` with direct binary exec | Both | High |
| Remove `GDK_SCALE=2` (double-scaling with Hyprland's monitor 2x scale) | Both | High |
| Use `programs.hyprlock.enable = true` at system level (auto-handles PAM) instead of raw `security.pam.services` | Gemini | High |
| Split `swww-daemon && swww img` into separate exec-once entries with delay | Codex | High |
| Add `papirus-icon-theme` package (rofi references `Papirus-Dark` but it wasn't installed) | Codex | Medium |
| Add explicit Syncthing firewall rules to `modules/nixos/core.nix` | Both | Medium |
| Move wallpaper to `assets/wallpaper.png` with correct relative path | Codex | Medium |
| Add verification notes for base16 scheme filename and font name | Both | Medium |
| Remove manual font-family from Waybar CSS (conflicts with Stylix-generated CSS) | Gemini | Medium |
| Add note to preserve NVIDIA `explicit_sync` settings during refactor | Gemini | Medium |
| Use `xdg.configFile` for wlogout config (no `programs.wlogout` HM module exists) | Codex | Medium |
| Simplify greetd config to use `programs.regreet.enable` (handles session wiring) | Codex | Low |
| Add Stylix HM integration verification step to Phase 1 acceptance criteria | Gemini | Low |
