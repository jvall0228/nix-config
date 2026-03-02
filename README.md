# nix-config

Multi-platform Nix configuration managed with flakes.

## Targets

| Host | OS | Arch | Status |
|------|----|------|--------|
| **thinkpad** | NixOS | x86_64-linux | Active |
| **proxmox-vm** | NixOS | x86_64-linux | Planned |
| **macbook** | macOS (nix-darwin) | aarch64-darwin | Planned |
| **arch** | Arch Linux (home-manager) | x86_64-linux | Planned |

## Structure

```
├── flake.nix              # Entry point
├── apps/                  # Convenience scripts (build-switch, clean)
├── assets/                # Wallpapers and static assets
├── hosts/                 # Per-machine configs + hardware
├── modules/
│   ├── shared/            # Cross-platform (nix settings)
│   └── nixos/             # NixOS system modules (core, audio, nvidia, hyprland, stylix, greetd, power)
└── home/
    ├── common/            # Cross-platform (shell, git, neovim, kitty, tmux, fastfetch, dev-tools)
    └── linux/             # Linux-only (hyprland, waybar, rofi, hyprlock, wlogout, swaync, starship, desktop)
```

## ThinkPad P15v Gen 3

- AMD Ryzen 7, NVIDIA RTX A2000
- Hyprland (Wayland), PipeWire
- LUKS + btrfs (zstd compression, async TRIM)
- Secure Boot via Lanzaboote
- TLP battery management with turbo boost control
- Kernel hardening (sysctls, module blacklist, memory init)

### Desktop Environment

- **Theming:** Stylix with Tokyo Night Dark (base16), Bibata cursor, Papirus icons
- **Fonts:** JetBrains Mono Nerd Font, Noto Sans/Serif, Noto Color Emoji
- **Bar:** Waybar (workspaces, clock, battery, CPU, volume, network, bluetooth, tray)
- **Launcher:** Rofi
- **Notifications:** SwayNC
- **Lock screen:** Hyprlock + Hypridle (5min lock, 15min suspend)
- **Power menu:** Wlogout (Super+M)
- **Login:** Greetd + ReGreet
- **Terminal:** Kitty, tmux (Tokyo Night), starship prompt
- **Apps:** Firefox, VS Code, Discord, Slack, Telegram, Obsidian, mpv, Nautilus

## Usage

```bash
# Rebuild and switch
sudo nixos-rebuild switch --flake .#thinkpad

# Or use the convenience scripts
bash apps/build-switch thinkpad
bash apps/clean
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
