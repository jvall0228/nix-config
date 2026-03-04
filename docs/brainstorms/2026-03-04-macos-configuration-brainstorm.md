# Brainstorm: macOS Configuration in nix-config

**Date:** 2026-03-04
**Status:** Draft
**Author:** javels + Claude
**Reference:** [dustinlyons/nixos-config](https://github.com/dustinlyons/nixos-config) — similar dual-platform Nix flake with Darwin + NixOS

## What We're Building

Add full macOS (Darwin) support to the nix-config repo, targeting an Apple Silicon MacBook Pro as a daily driver. This includes nix-darwin system configuration, home-manager integration, Aerospace tiling WM, comprehensive macOS system preferences, Homebrew cask management for GUI apps, and Stylix + manual hybrid theming.

## Why This Approach

**Parallel module structure** — mirroring the existing `modules/nixos/` and `home/linux/` pattern with `modules/darwin/` and `home/darwin/`. This follows the repo's established conventions, keeps platform concerns cleanly separated, and is easy to navigate.

The repo is already architected for this: `modules/shared/` and `home/common/` exist for cross-platform config, `specialArgs` passes `system`, and there are explicit TODOs in `flake.nix` for `darwinConfigurations`. Dustin Lyons' nixos-config confirms this is a proven pattern for dual-platform Nix flakes.

## Key Decisions

1. **Target:** Apple Silicon MacBook Pro (aarch64-darwin)
2. **Host name:** `macbook-pro`
3. **Module structure:** Parallel — `modules/darwin/` + `home/darwin/` as peers to NixOS equivalents
4. **Window management:** Aerospace (i3-inspired tiling WM), configured in `home/darwin/` (user-level, consistent with Hyprland being in `home/linux/`)
5. **Theming:** Stylix for terminal/app targets that work on Darwin + manual macOS system appearance config
6. **System preferences:** Comprehensive — Dock, Finder, trackpad, keyboard, screenshots, security, etc. managed declaratively via `system.defaults`
7. **App installation:** Homebrew casks via nix-darwin's `homebrew` module for GUI apps; Nix for CLI tools
8. **Home-manager:** Via `home-manager.darwinModules.home-manager` (same pattern as NixOS integration)
9. **Bootstrap:** Create `apps/bootstrap-darwin` script that installs Nix, Homebrew, and runs first build

## Scope

### New flake inputs
- `nix-darwin` (github:LnL7/nix-darwin)

### New directories/files
- `hosts/macbook-pro/default.nix` — Host-specific config (hostname, macOS defaults)
- `modules/darwin/core.nix` — Core Darwin system config (system preferences, security, services)
- `modules/darwin/homebrew.nix` — Homebrew cask declarations
- `home/darwin/default.nix` — Darwin-specific home-manager entry (imports darwin modules)
- `home/darwin/aerospace.nix` — Aerospace keybindings and settings
- `home/darwin/desktop.nix` — macOS desktop apps, menu bar utilities
- `apps/build-switch-darwin` — Build script for Darwin (like `apps/build-switch`)
- `apps/bootstrap-darwin` — Zero-to-working bootstrap script (installs Nix, Homebrew, clones repo, first build)

### Modified files
- `flake.nix` — Add nix-darwin input, `darwinConfigurations.macbook-pro` block, aarch64-darwin apps
- `home/default.nix` — Add Darwin conditional imports (alongside existing Linux ones), fix `homeDirectory` for `/Users/${user}`
- `CLAUDE.md` — Document Darwin workflow and conventions

### Shared config (already works cross-platform)
- `modules/shared/nix.nix` — Nix settings
- `home/common/*` — Shell, git, neovim, kitty, tmux, fastfetch, dev-tools

## Resolved Questions

1. **Host naming:** `macbook-pro` — matching the hardware, consistent with `thinkpad`.
2. **Aerospace location:** `home/darwin/` (user-level) — Aerospace is a user-space app, consistent with Hyprland config being in `home/linux/`.
3. **Homebrew bootstrap:** Create `apps/bootstrap-darwin` script that automates Nix + Homebrew installation and first build.

## Resolved Questions (continued)

4. **Stylix Darwin scope:** Stylix officially supports nix-darwin via `stylix.darwinModules.stylix`. It themes **applications only** through Home Manager targets — kitty, bat, starship, neovim, btop work well. It **cannot** control macOS system appearance (dark mode, accent color, Dock, menu bar). GTK targets are irrelevant on macOS. Strategy: use Stylix for app-level theming (terminal, editors), set macOS dark mode and accent color via `system.defaults` in nix-darwin separately.
