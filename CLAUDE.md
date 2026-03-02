# nix-config — Agent Instructions

## What This Is

A flake-based Nix configuration repo managing multiple machines. The primary target is a ThinkPad P15v Gen 3 running NixOS with Hyprland.

## Repo Layout

- `flake.nix` — Entry point. Defines all host configurations and inputs.
- `hosts/<name>/` — Per-machine config. Each host has `default.nix`, `hardware-configuration.nix`, and optionally `disko.nix`.
- `modules/shared/` — Nix settings shared across NixOS and Darwin.
- `modules/nixos/` — NixOS-specific system modules (boot, audio, nvidia, hyprland, power, stylix, greetd).
- `home/` — home-manager config. `common/` is cross-platform, `linux/` is Linux-specific.
- `home/linux/` — Hyprland, waybar, rofi, hyprlock, wlogout, swaync, starship, desktop apps.
- `home/common/` — Shell, git, neovim, kitty, tmux, fastfetch, dev-tools.
- `apps/` — Shell scripts for common operations (run directly with `bash apps/<name>`).
- `assets/` — Wallpapers and static assets.

## Conventions

- **Language:** Nix (the language). All `.nix` files.
- **User variable:** Parameterized via `specialArgs` as `user`. Never hardcode `javels` in modules — use `${user}`.
- **Unstable packages:** Available via `unstable` in `specialArgs`. Use for packages that need bleeding edge (e.g., `unstable.claude-code`).
- **Platform guards:** Use `lib.optionals pkgs.stdenv.isLinux` / `isDarwin` for platform-specific imports.
- **Adding a host:** Create `hosts/<name>/default.nix`, add a `nixosConfigurations.<name>` block in `flake.nix`, pick modules.
- **State version:** `25.05` — do not change this on existing hosts.

## Key Patterns

- Modules use `{ ... }:` or `{ pkgs, user, config, ... }:` destructuring — only bind what's needed.
- `hardware-configuration.nix` is machine-generated. Don't hand-edit it.
- `disko.nix` defines declarative disk layout. Only modify when changing partition scheme.
- System packages go in `modules/nixos/core.nix`. User packages go in `home/common/dev-tools.nix` or platform-specific home modules.
- Stylix (`modules/nixos/stylix.nix`) manages theming globally — Tokyo Night Dark, JetBrains Mono NF, Bibata cursor. It auto-targets kitty, waybar, hyprlock, GTK, QT. Use `stylix.targets.<name>.enable = false` to opt out specific apps. Don't set `qt.platformTheme` or manual color configs that conflict with Stylix.
- `rofi-wayland` was merged into `rofi` in nixpkgs 25.11 — use `pkgs.rofi`.
- `render.explicit_sync` was removed from Hyprland — explicit sync is always on.
- Hyprland `exec-once` and `bind` entries using pipes, `$()`, or `&&` must be wrapped in `sh -c '...'`.

## Agent Workflow (NixOS Operations)

All `sudo` commands are passwordless for the wheel-group user.

- **Rebuild system:** `bash apps/build-switch` (auto-detects hostname, uses absolute flake path)
- **Rebuild specific host:** `bash apps/build-switch thinkpad`
- **Dry-build (no sudo needed):** `nixos-rebuild dry-build --flake ~/nix-config#$(hostname)`
- **Rollback:** `sudo nixos-rebuild switch --rollback`
- **Garbage collect:** `bash apps/clean`
- **Check system health:** `systemctl is-system-running` (no sudo needed)
- **Read build logs on failure:** `journalctl -u nixos-rebuild.service -n 100` or `nix log /nix/store/<drv>`
- **Update flake inputs:** `nix flake update` (no sudo needed)

### Constraints

- **Generation limit:** Lanzaboote limits to 10 bootloader entries. Don't apply 10+ broken configs without fixing.
- **Auto-upgrade:** Runs at 04:00 from `github:jvall0228/nix-config/main`. Local uncommitted changes will be overwritten. Commit and push before expecting persistence.
## Do Not

- Hardcode usernames — use the `user` variable.
- Change `system.stateVersion` or `home.stateVersion` on deployed hosts.
- Edit `hardware-configuration.nix` manually.
- Add NixOS-specific options in `home/common/` (use `home/linux/`).
