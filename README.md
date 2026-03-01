# nix-config

Multi-platform Nix configuration managed with flakes.

## Targets

| Host | OS | Arch | Status |
|------|----|------|--------|
| **thinkpad** | NixOS | x86_64-linux | Active |
| **macbook** | macOS (nix-darwin) | aarch64-darwin | Future |
| **proxmox-vm** | NixOS | x86_64-linux | Future |
| **arch** | Arch Linux (home-manager) | x86_64-linux | Future |

## Structure

```
├── flake.nix              # Entry point
├── apps/                  # Convenience scripts (build-switch, clean)
├── hosts/                 # Per-machine configs + hardware
├── modules/
│   ├── shared/            # Cross-platform (nix settings)
│   ├── nixos/             # NixOS system modules
│   └── darwin/            # macOS system modules (future)
└── home/
    ├── common/            # Cross-platform home-manager
    ├── linux/             # Linux-only (Hyprland, GUI apps)
    └── darwin/            # macOS-only (future)
```

## ThinkPad P15v Gen 3

- AMD Ryzen 7, NVIDIA RTX A2000
- Hyprland (Wayland), PipeWire, LUKS + btrfs
- TLP battery management

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

See the install steps in [the plan](https://github.com/jvall0228/nix-config) or follow the NixOS manual. Key steps:

1. Boot NixOS minimal ISO
2. Clone this repo
3. Run disko for partitioning
4. Generate `hardware-configuration.nix`
5. `sudo nixos-install --flake .#thinkpad`
