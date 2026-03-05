# Portable Dotfiles with Nix Config

**Date:** 2026-03-05
**Status:** Brainstorm complete

## What We're Building

A separate dotfiles repo that serves as the **source of truth** for shell, neovim, kitty, and tmux configurations. The dotfiles are portable plain config files managed by **GNU Stow** on non-Nix machines, and consumed by **nix-config via runtime path references** on Nix-managed machines.

## Why This Approach

- **Dotfiles are primary** — Raw config files are the source of truth, not Nix expressions. This means configs work anywhere, and Nix wraps them rather than generating them.
- **GNU Stow for non-Nix** — Zero-magic symlink farm. Selective installs (`stow neovim`, `stow kitty`). No templating engine or state to manage.
- **Runtime path for Nix integration** — `home.file.source = ~/dotfiles/...` keeps things simple and always in sync. Matches existing pattern of `~/nix-config/assets/` runtime references.

## Scope

Configs to extract from nix-config into the dotfiles repo:

| Config | Current Location | Dotfiles Path | Notes |
|--------|-----------------|---------------|-------|
| Shell aliases & env | `home/common/shell.nix` | `shell/.config/shell/aliases` | Extract from `home.shellAliases` |
| Bash config | `home/common/shell.nix` | `shell/.bashrc` | Minimal, sources aliases |
| Starship prompt | `home/linux/starship.nix` | `shell/.config/starship.toml` | Remove NixOS-specific symbol |
| Neovim | `home/common/neovim.nix` | `neovim/.config/nvim/` | Full nvim config dir |
| Kitty | `home/common/kitty.nix` | `kitty/.config/kitty/kitty.conf` | Pure settings, no Nix deps |
| Tmux | `home/common/tmux.nix` | `tmux/.config/tmux/tmux.conf` | Plugin mgmt needs consideration |

## Key Decisions

1. **Dotfiles are source of truth** — Nix reads from them, not the other way around.
2. **GNU Stow** for non-Nix bootstrap — simple, well-understood, minimal deps.
3. **Separate repo** — standalone dotfiles repo, not a subdirectory of nix-config.
4. **Runtime path references** — `~/dotfiles/` is referenced directly by home-manager modules. No flake input indirection.
5. **Selective extraction** — Only shell, neovim, kitty, tmux. Linux-specific configs (Hyprland, waybar, AGS) stay in nix-config since they're inherently Nix/NixOS-coupled.
6. **TPM for tmux plugins** — Use TPM everywhere (including Nix machines) instead of `pkgs.tmuxPlugins`. One plugin system, fully portable.
7. **Stylix overrides on Nix** — Dotfiles carry a base color scheme. On Nix machines, Stylix auto-theming still applies and overrides colors. Slight drift is acceptable since Nix machines get the "enhanced" version.
8. **lazy.nvim for neovim** — Full neovim extraction with lazy.nvim for portable plugin management. Nix just points `xdg.configFile."nvim"` at the dotfiles config dir.

## Architecture

```
~/dotfiles/                    # Separate repo, Stow-compatible layout
├── shell/
│   ├── .bashrc
│   ├── .config/
│   │   ├── shell/aliases      # Shared aliases
│   │   └── starship.toml
├── neovim/
│   └── .config/nvim/
│       └── init.lua (+ lua/)
├── kitty/
│   └── .config/kitty/
│       └── kitty.conf
├── tmux/
│   └── .config/tmux/
│       └── tmux.conf
├── install.sh                 # Optional: fallback if Stow unavailable
└── README.md

~/nix-config/                  # Existing repo
├── home/common/
│   ├── shell.nix              # → xdg.configFile.source = ~/dotfiles/shell/...
│   ├── neovim.nix             # → xdg.configFile."nvim".source = ~/dotfiles/neovim/.config/nvim
│   ├── kitty.nix              # → xdg.configFile.source = ~/dotfiles/kitty/...
│   └── tmux.nix               # → xdg.configFile.source = ~/dotfiles/tmux/...
```

### Non-Nix workflow
```bash
git clone <dotfiles-repo> ~/dotfiles
cd ~/dotfiles
stow shell neovim kitty tmux    # Creates symlinks into ~/
```

### Nix workflow
```bash
# dotfiles repo must be cloned at ~/dotfiles
# home-manager modules reference files directly:
# xdg.configFile."nvim".source = /home/${user}/dotfiles/neovim/.config/nvim;
```

## Resolved Questions

1. **Tmux plugins** → **TPM only.** Switch fully to TPM even on Nix machines. One plugin system everywhere.
2. **Stylix theming** → **Stylix overrides on Nix.** Dotfiles carry a base theme. Stylix auto-themes on Nix machines, which may drift slightly from the portable version — acceptable tradeoff.
3. **Neovim plugins** → **Full extraction with lazy.nvim.** Portable plugin management via lazy.nvim. Nix just sources the config directory.
