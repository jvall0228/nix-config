# nix-config

Multi-platform Nix configuration managed with flakes.

## Targets

| Host | OS | Arch | Status |
|------|----|------|--------|
| **thinkpad** | NixOS | x86_64-linux | Active |
| **proxmox-vm** | NixOS | x86_64-linux | Planned |
| **macbook-pro** | macOS (nix-darwin) | aarch64-darwin | Active |
| **arch** | Arch Linux (home-manager) | x86_64-linux | Planned |

## Structure

```
├── flake.nix              # Entry point
├── apps/                  # Convenience scripts (build-switch, build-switch-darwin, bootstrap-darwin, clean)
├── assets/                # Wallpapers and static assets
├── hosts/                 # Per-machine configs + hardware
├── modules/
│   ├── shared/            # Cross-platform (nix settings, stylix base)
│   ├── nixos/             # NixOS system modules (core, audio, nvidia, hyprland, stylix, greetd, power, agent-context)
│   └── darwin/            # Darwin system modules (system.defaults, homebrew, stylix)
└── home/
    ├── common/            # Cross-platform (shell, git, neovim, kitty, tmux, fastfetch, dev-tools)
    ├── linux/             # Linux-only (hyprland, waybar, ags, rofi, walker, hyprlock, wlogout, swaync, starship, wallpaper, capture, desktop)
    └── darwin/            # macOS-only (aerospace)
```

## ThinkPad P15v Gen 3

- AMD Ryzen 7, NVIDIA RTX A2000
- Hyprland (Wayland), PipeWire
- LUKS + btrfs (zstd compression, async TRIM)
- Secure Boot via Lanzaboote
- TLP battery management with turbo boost control
- Kernel hardening (sysctls, module blacklist, memory init)
- Hardware profiles via nixos-hardware (AMD CPU, laptop, SSD)

### Desktop Environment

- **Theming:** Stylix with Tokyo Night Dark (base16), Bibata cursor, Papirus icons
- **Fonts:** JetBrains Mono Nerd Font, Noto Sans/Serif, Noto Color Emoji
- **Bar:** Waybar (workspaces, clock, battery, CPU, memory, temperature, GPU, disk, volume, network, bluetooth, media, weather, tray)
- **Widgets:** AGS (dashboard, audio mixer, bluetooth, calendar, media, network, notifications, OSD)
- **Launcher:** Rofi, Walker
- **Lock screen:** Hyprlock + Hypridle (5min lock, no auto-suspend — limited S3 deep sleep support)
- **Power menu:** Wlogout (Super+M)
- **Login:** Greetd + ReGreet
- **Terminal:** Kitty, tmux (Tokyo Night), starship prompt
- **Apps:** Firefox, VS Code, Discord, Slack, Telegram, Obsidian, mpv, Nautilus

## MacBook Pro (Darwin)

- Aerospace tiling window manager
- Stylix theming (Tokyo Night Dark, shared base with NixOS)
- Homebrew casks for GUI apps (auto-managed on rebuild)
- Touch ID sudo in tmux (via pam-reattach)
- Nix garbage collection via launchd

## Usage

```bash
# NixOS — rebuild and switch
bash apps/build-switch thinkpad

# Darwin — rebuild and switch
bash apps/build-switch-darwin macbook-pro

# Bootstrap a fresh Mac
bash apps/bootstrap-darwin

# Garbage collect
bash apps/clean

# System health check
bash apps/system-status
```

## Adding a Host

1. Create `hosts/<name>/default.nix`
2. Add `nixosConfigurations.<name>` (or `darwinConfigurations`) to `flake.nix`
3. Pick which modules to include

## Install

1. Boot NixOS minimal ISO
2. Clone this repo
3. Run disko for partitioning
4. Generate `hardware-configuration.nix`
5. `sudo nixos-install --flake .#thinkpad`
6. Enroll Secure Boot keys: `sbctl create-keys` and `sbctl enroll-keys --microsoft`
