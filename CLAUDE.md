# nix-config — Agent Instructions

## What This Is

A flake-based Nix configuration repo managing multiple machines. The primary target is a ThinkPad P15v Gen 3 running NixOS with Hyprland.

## Repo Layout

- `flake.nix` — Entry point. Defines all host configurations and inputs.
- `hosts/<name>/` — Per-machine config. Each host has `default.nix`, `hardware-configuration.nix`, and optionally `disko.nix`.
- `modules/shared/` — Nix settings shared across NixOS and Darwin.
- `modules/nixos/` — NixOS-specific system modules (boot, audio, nvidia, hyprland, power).
- `home/` — home-manager config. `common/` is cross-platform, `linux/` is Linux-specific.
- `apps/` — Shell scripts for common operations (run directly with `bash apps/<name>`).

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

## Do Not

- Hardcode usernames — use the `user` variable.
- Change `system.stateVersion` or `home.stateVersion` on deployed hosts.
- Edit `hardware-configuration.nix` manually.
- Add NixOS-specific options in `home/common/` (use `home/linux/`).
