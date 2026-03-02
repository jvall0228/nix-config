# Brainstorm: NixOS Daily Driver + Rice

**Date:** 2026-03-02
**Status:** Final

## What We're Building

Transform the current bare-bones Hyprland NixOS setup into a fully daily-drivable workstation with a cohesive Tokyo Night rice. The system should be a full workstation: development, browsing, media, communication, document editing, and file management.

## Why This Approach

The foundation is solid — Hyprland, PipeWire, NVIDIA, secure boot, LUKS encryption are all working. But every user-facing tool (waybar, kitty, mako, wofi) runs on stock defaults, there's no theming, missing essential keybindings, no lock screen, and no communication apps. The goal is to close all these gaps in one cohesive pass using the Tokyo Night color scheme that's already established across the user's macOS dotfiles.

## Key Decisions

### Theming: Stylix (system-wide)
- Use Stylix flake for unified theming across all applications
- Single source of truth for colors, fonts, wallpaper
- Auto-themes: Hyprland borders, waybar, kitty, GTK, cursor, greetd, and more
- Tokyo Night as the base16 color scheme
- Replaces manual per-tool theming — more consistent, less maintenance

### Tokyo Night Palette Reference
```
bg:        #1a1b26
bg-dark:   #16161e
bg-float:  #292e42
fg:        #c0caf5
blue:      #7aa2f7
cyan:      #7dcfff
green:     #9ece6a
magenta:   #bb9af7
orange:    #ff9e64
red:       #f7768e
yellow:    #e0af68
comment:   #565f89
selection: #283457
```

### Font: JetBrains Mono Nerd Font
- Already used on macOS kitty config
- Full coverage: JetBrains Mono NF + Noto Color Emoji + Noto Sans CJK
- Currently only have nerd-fonts.symbols-only — need to add full packages

### Launcher: rofi-wayland (replaces wofi)
- Rofi 2.0+ has native Wayland support
- Massive theme ecosystem, community standard for Hyprland rices
- Better styling and customization than wofi

### Notifications: SwayNC (replaces mako)
- Full notification center with history panel (toggle with keybind or Waybar module)
- Do Not Disturb mode
- Urgency-differentiated styling: low = subtle, normal = blue border, critical = red + persist
- GTK-based, will pick up Stylix theming

### Waybar: Full-featured (match sketchybar parity)
- Position: top
- Modules: workspaces, active window, clock/calendar, battery, CPU, volume, wifi, media (playerctl)
- Styled with Tokyo Night colors, rounded modules

### GTK: Stylix-managed
- Stylix handles GTK theme generation from Tokyo Night palette
- Papirus Dark icons + cursor theme (Bibata Modern Classic or similar, Stylix-managed)

### Neovim: Hybrid approach
- Nix installs neovim + external deps (LSPs, formatters, tree-sitter)
- LazyVim Lua config manages plugins via lazy.nvim
- Existing shared-dotfiles nvim config as the base

### Starship: Redesign for NixOS
- Keep the Tokyo Night blue-gradient powerline style from macOS
- Replace Apple icon with NixOS/Linux icon
- Platform-specific configs: base in `home/common/`, icon override in `home/linux/` (future `home/darwin/`)

### Terminal tooling to port from macOS dotfiles
- **Kitty:** JetBrains Mono Nerd Font, Tokyo Night (Stylix-managed), HiDPI font size
- **Tmux:** Tokyo Night theme, top status bar, Nix-managed plugins via home-manager `programs.tmux`
- **Fastfetch:** Custom config with NixOS logo, system info modules

## Scope Breakdown

### 1. Daily-Driver Essentials (functional)
- [ ] greetd + regreet (graphical login greeter, dark themed, GDM-like UX; tuigreet as fallback)
- [ ] hyprlock + hypridle (lock screen on idle/lid close, suspend after timeout)
- [ ] XF86 keybindings (volume via `wpctl`, brightness via `brightnessctl`, media via `playerctl`)
- [ ] Communication apps: Discord, Slack, Telegram, Obsidian (Electron Wayland flags via global env var)
- [ ] Media: VLC or mpv
- [ ] File sync: Syncthing
- [ ] More workspaces (bind 1-9 for both switch and move-to-workspace, currently only 1-5)
- [ ] Clipboard manager (cliphist)
- [ ] File manager (Nautilus)
- [ ] Bluetooth management (blueman — no BT tooling exists currently)
- [ ] Network management UX (nm-applet — NetworkManager exists but has no GUI)
- [ ] Polkit agent (needed for GUI auth prompts)
- [ ] wlogout (visual power menu for lock/logout/suspend/reboot/shutdown)
- [ ] XDG desktop portals (xdg-desktop-portal-hyprland + gtk — screen sharing, file dialogs)
- [ ] Screenshot UX (grim + slurp + save-to-disk, consider swappy for annotation)
- [ ] swayosd (on-screen display for volume/brightness/capslock feedback)
- [ ] playerctl (media key control — play/pause/next/prev)
- [ ] wl-screenrec (GPU-accelerated screen recording)

### 2. Rice — Desktop Shell
- [ ] Stylix integration (flake input, base16 Tokyo Night scheme, fonts, wallpaper — single theming source)
- [ ] Waybar config (full widget set, Stylix-themed)
- [ ] rofi-wayland config (replace wofi, Stylix-themed)
- [ ] SwayNC config (replace mako, urgency-differentiated, notification center)
- [ ] Hyprland border colors + animations (fade, slide, resize — Stylix colors)
- [ ] Wallpaper (Tokyo Night-vibe wallpaper via swww, Stylix wallpaper source)
- [ ] GTK/QT theme (Stylix-managed, Papirus Dark icons, cursor theme)
- [ ] HiDPI coordination (GDK/QT scale env vars, Xwayland scaling, coordinated font sizes at 2x)
- [ ] hyprpicker (color picker utility)
- [ ] wlsunset (night light / blue light filter)
- [ ] Plymouth (themed boot splash matching Tokyo Night)

### 3. Rice — Terminal
- [ ] Kitty config (Tokyo Night via Stylix, JetBrains Mono, HiDPI font size)
- [ ] Tmux config (Tokyo Night theme, top bar — home-manager `programs.tmux` with Nix-managed plugins)
- [ ] Starship prompt (redesign from macOS to NixOS, Tokyo Night colors, platform-specific configs)
- [ ] Fastfetch config (NixOS logo, system modules)

### 4. Rice — Editor
- [ ] Neovim hybrid setup (extend existing `home/common/neovim.nix` with extraPackages for LSPs + LazyVim Lua config)
- [ ] LSP servers installed via Nix (lua-ls, pyright, rust-analyzer, typescript-language-server, nil for Nix)

### 5. Rice — Extras
- [ ] hyprexpo plugin (workspace overview, Expose-like)
- [ ] waypaper (GUI wallpaper picker, uses swww backend)

### Scope dependencies
- Stylix should be integrated first — it provides the foundation for all theming
- greetd+regreet depends on GTK/Stylix theming being set up (it's a GTK4 greeter)
- Essentials (section 1) should be functional before polish (sections 2-5)
- Electron Wayland flags depend on environment variables in Hyprland config
- hyprexpo plugin requires matching Hyprland version (NixOS flake handles this)

## Architecture Notes

All configuration should be managed through home-manager where possible, keeping the existing repo structure:
- Desktop/GUI configs → `home/linux/`
- Terminal/shell configs → `home/common/` (cross-platform)
- System packages → `modules/nixos/core.nix`
- User packages → `home/common/dev-tools.nix` or platform-specific modules
- Stylix → system-level in `flake.nix` (flake input) + config in a shared module

## Open Questions

1. **HiDPI details** — Sensible defaults will be chosen during planning (font sizes, scale env vars). Adjust after testing.
2. **Hyprland animation values** — Sensible defaults will be chosen during planning (durations, bezier curves). Adjust after testing.

## Resolved Questions

1. **Wallpaper choice** — Source a Tokyo Night-vibe wallpaper (not using existing macOS wallpapers).
2. **Hyprland animations** — Enable animations (fade, slide, resize). Dial back if NVIDIA causes issues.
3. **Login manager** — greetd + regreet (GTK4 graphical greeter, GDM-like UX, dark themed). Fallback: tuigreet.
4. **Notification urgency styling** — Differentiated via SwayNC. Low = subtle/dim, Normal = blue border, Critical = red + persist.
5. **File manager** — Nautilus (GNOME's file manager).
6. **Tmux plugin management** — home-manager `programs.tmux` with Nix-managed plugins. Fully declarative.
7. **Starship platform split** — Platform-specific configs. Base in `home/common/`, icon override in `home/linux/` (and future `home/darwin/`).
8. **Font packages** — Full coverage: JetBrains Mono Nerd Font + Noto Color Emoji + Noto Sans CJK.
9. **Cursor theme** — Stylix-managed. Dark aesthetic (Bibata Modern Classic or Phinger Cursors).
10. **Desktop apps location** — Add to existing `home/linux/desktop.nix`.
11. **Electron Wayland strategy** — Global `ELECTRON_OZONE_PLATFORM_HINT=auto` env var in Hyprland config.
12. **Theming approach** — Stylix for system-wide unified theming (replaces manual per-tool configuration).
13. **Launcher** — rofi-wayland (replaces wofi). Better ecosystem and styling.
14. **Notifications** — SwayNC (replaces mako). Notification center with history, DND, urgency styling.

## Validation Strategy

- Dry-build (`nixos-rebuild dry-build`) after each module change to catch Nix eval errors early
- Test hyprlock manually before enabling hypridle (avoid getting locked out with a broken lock screen)
- Test greetd+regreet on a separate TTY or after confirming the config builds, with a known-good TTY login as fallback
- Screenshot before/after for visual comparison of the rice
- Test all XF86 keybindings (volume, brightness, mic mute, media) with hardware keys
- Verify Electron apps (Discord, Slack, VSCode) render correctly under Wayland — check for blank windows, scaling issues
- Test Stylix theming propagation across all targets

## Codebase Reference (current state)

Files that will be modified or extended:
| File | Current state | Planned changes |
|------|--------------|-----------------|
| `flake.nix` | NixOS config with home-manager | Add Stylix flake input + module |
| `home/linux/hyprland.nix` | Basic bindings (1-5 workspaces), no animations, no colors, swww-daemon in exec-once | Add workspaces 6-9, animations, XF86 binds, wallpaper command, hyprlock/hypridle, env vars, swayosd/swaync/rofi/wlogout integration |
| `home/linux/desktop.nix` | Firefox, VSCode, symbols-only nerd font | Add JetBrains Mono NF, emoji/CJK fonts, communication apps, file manager, new desktop tools |
| `home/common/shell.nix` | Bash aliases + starship enabled (no config) | Add starship config (Tokyo Night, platform-split) |
| `home/common/neovim.nix` | Basic enable + aliases | Add extraPackages for LSPs, symlink LazyVim config |
| `home/common/dev-tools.nix` | CLI tools + bare tmux package | Move tmux to home-manager `programs.tmux` |
| `modules/nixos/core.nix` | System packages, sudo, networking | Add system-level packages (polkit agent, greetd, plymouth) |
| `modules/nixos/hyprland.nix` | System-level Hyprland enable | Add XDG portals, env vars |

New files likely needed:
- `home/linux/waybar.nix` — waybar config + modules
- `home/linux/swaync.nix` — notification center config
- `home/linux/rofi.nix` — launcher config
- `home/linux/gtk.nix` — GTK/QT/cursor/icon config (if not fully handled by Stylix)
- `home/linux/hyprlock.nix` — lock screen config
- `home/linux/wlogout.nix` — power menu config
- `home/common/kitty.nix` — terminal config (cross-platform)
- `home/common/tmux.nix` — tmux config
- `home/common/fastfetch.nix` — system info display
- `modules/shared/stylix.nix` — Stylix theme configuration

## Research References

- [Frost-Phoenix/nixos-config](https://github.com/Frost-Phoenix/nixos-config) — 888 stars, comprehensive NixOS Hyprland rice
- [XNM1/linux-nixos-hyprland-config-dotfiles](https://github.com/XNM1/linux-nixos-hyprland-config-dotfiles) — 873 stars, Catppuccin-themed
- [anotherhadi/nixy](https://github.com/anotherhadi/nixy) — 477 stars, Stylix-driven theming (key reference for Stylix integration)
- [Stylix (nix-community)](https://github.com/nix-community/stylix) — Theming framework for NixOS
- [Hyprland Wiki - Useful Utilities](https://wiki.hypr.land/Useful-Utilities/Must-have/) — Official tool recommendations
