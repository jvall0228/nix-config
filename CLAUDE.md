# nix-config — Agent Instructions

## What This Is

A flake-based Nix configuration repo managing multiple machines. Targets a ThinkPad P15v Gen 3 (NixOS/Hyprland) and a MacBook Pro (Darwin/Aerospace).

## Repo Layout

- `flake.nix` — Entry point. Defines all host configurations and inputs.
- `hosts/<name>/` — Per-machine config. Each host has `default.nix`, `hardware-configuration.nix`, and optionally `disko.nix`.
- `modules/shared/` — Nix settings shared across NixOS and Darwin.
- `modules/nixos/` — NixOS-specific system modules (core, audio, nvidia, hyprland, power, stylix, greetd, agent-context).
- `modules/darwin/` — Darwin-specific system modules (system.defaults, homebrew, stylix).
- `home/` — home-manager config. `common/` is cross-platform, `linux/` is Linux-specific, `darwin/` is macOS-specific.
- `home/linux/` — Hyprland, waybar, AGS, rofi, walker, hyprlock, wlogout, swaync, starship, wallpaper, capture, desktop apps.
- `home/darwin/` — Aerospace tiling WM, zsh config.
- `home/common/` — Shell, git, neovim, kitty, tmux, fastfetch, dev-tools.
- `apps/` — Shell scripts for common operations (run directly with `bash apps/<name>`).
- `assets/` — Wallpapers and static assets.

## Flake Inputs

- `nixpkgs` / `nixpkgs-unstable` — stable (25.11) and unstable package sets.
- `home-manager` — user-level config (release-25.11, follows nixpkgs).
- `nixos-hardware` — hardware-specific optimizations (AMD CPU, laptop, SSD).
- `disko` — declarative disk partitioning.
- `lanzaboote` — Secure Boot (v1.0.0).
- `stylix` — system-wide theming (release-25.11).
- `walker` — application launcher.
- `ags` / `astal` — shell widgets (AGS v3 with Astal library).
- `nix-darwin` — macOS system management (nix-darwin-25.11).

## Conventions

- **Language:** Nix (the language). All `.nix` files.
- **User variable:** Parameterized via `specialArgs` as `user`. Never hardcode `javels` in modules — use `${user}`.
- **specialArgs:** NixOS and Darwin system modules receive `inputs`, `user`, `unstable`. Home-manager modules receive `inputs`, `user`, `system`, `unstable` via `extraSpecialArgs`.
- **Unstable packages:** Available via `unstable` in `specialArgs`. Use for packages that need bleeding edge (e.g., `unstable.claude-code`).
- **Platform guards:** In system modules use `lib.mkIf pkgs.stdenv.isLinux`. In `home/default.nix`, platform detection uses `builtins.elem system [ "x86_64-linux" ... ]` with the `system` specialArg.
- **Adding a host:** Create `hosts/<name>/default.nix`, add a `nixosConfigurations.<name>` (or `darwinConfigurations.<name>`) block in `flake.nix`, pick modules.
- **State version:** NixOS uses `"25.05"` (string). Darwin uses `6` (integer). Do not change on existing hosts.

## Key Patterns

- Modules use `{ ... }:` or `{ pkgs, user, config, ... }:` destructuring — only bind what's needed.
- `hardware-configuration.nix` is machine-generated. Don't hand-edit it.
- `disko.nix` defines declarative disk layout. Only modify when changing partition scheme.
- System packages go in `modules/nixos/core.nix`. User packages go in `home/common/dev-tools.nix` or platform-specific home modules.
- Stylix is split across three files: `modules/shared/stylix.nix` (base colors, monospace font), `modules/nixos/stylix.nix` (sans/serif/emoji fonts, cursor, `autoEnable = true`), `modules/darwin/stylix.nix` (`autoEnable = false` — HM-level targets like kitty/bat/btop still auto-theme). Use `stylix.targets.<name>.enable = false` to opt out specific apps. Don't set `qt.platformTheme` or manual color configs that conflict with Stylix.
- AGS uses `configDir` with `symlinkJoin` to inject a generated `colors.css` from Stylix base16 colors into the config directory. See `home/linux/ags.nix`.
- When a program lacks a home-manager module (e.g., Aerospace), write config directly via `home.file."<path>".text`.
- `rofi-wayland` was merged into `rofi` in nixpkgs 25.11 — use `pkgs.rofi`.
- `render.explicit_sync` was removed from Hyprland — explicit sync is always on.
- Hyprland `exec-once` and `bind` entries using pipes, `$()`, or `&&` must be wrapped in `sh -c '...'`.

## System Context

This system is NixOS 25.11, x86_64-linux, kernel 6.12.74.
Flake: ~/nix-config#thinkpad.
GPU: AMD Rembrandt Radeon 680M + NVIDIA (discrete, via nvidia.nix).

Do NOT run discovery commands like `uname`, `lspci`, or directory exploration — use this section instead.

For a full system context dump (also usable by non-Claude agents): `cat /etc/agent-context.md`
For system health check: `bash apps/system-status`

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

## Agent Workflow (Darwin Operations)

- **Rebuild system:** `bash apps/build-switch-darwin` (auto-detects hostname)
- **Rebuild specific host:** `bash apps/build-switch-darwin macbook-pro`
- **Bootstrap fresh Mac:** `bash apps/bootstrap-darwin`
- **Dry-build:** `darwin-rebuild build --flake ~/nix-config#macbook-pro`
- **Homebrew casks:** Auto-updated on every `darwin-rebuild switch`

### Darwin-Specific Constraints

- **No Lanzaboote/disko:** Darwin has no bootloader or disk config to manage.
- **Homebrew required:** Must be installed before `darwin-rebuild switch`. Bootstrap handles this.
- **stateVersion is integer:** nix-darwin uses `system.stateVersion = 6` (not a string).
- **No auto-upgrade:** Darwin requires manual rebuilds (no equivalent to `system.autoUpgrade`).
- **Touch ID sudo in tmux:** Requires `pam-reattach`. Installed by `modules/darwin/core.nix`.
- **nix flake check:** Must use `--system x86_64-linux` on NixOS or `--system aarch64-darwin` on Mac.
- **Store optimization:** `auto-optimise-store` is disabled on Darwin (corrupts store). Run `nix store optimise` manually if store grows large.
- **trusted-users:** The unprivileged user is in `trusted-users` for passwordless darwin-rebuild. This is a security tradeoff — see `modules/shared/nix.nix`.

## Do Not

- Hardcode usernames — use the `user` variable.
- Change `system.stateVersion` or `home.stateVersion` on deployed hosts.
- Edit `hardware-configuration.nix` manually.
- Add NixOS-specific options in `home/common/` (use `home/linux/`).
- Add Darwin-specific options in `home/common/` (use `home/darwin/`).
