---
title: "feat: Add Walker as Raycast-like unified command palette"
type: feat
status: active
date: 2026-03-02
origin: docs/brainstorms/2026-03-02-raycast-ux-linux-brainstorm.md
---

# feat: Add Walker as Raycast-like unified command palette

## Overview

Add [Walker](https://github.com/abenz1267/walker) as a Raycast-style unified command palette on `SUPER+Space`, while keeping rofi as a fallback on `SUPER+D`. Walker provides prefix-based module activation (`=` calc, `/` files, `:` clipboard, `.` symbols, `$` windows, `@` websearch, `>` runner), a persistent daemon for instant popup, and a plugin system for custom extensions.

This is a two-phase rollout: Phase 1 delivers core Walker integration with built-in modules. Phase 2 (future, not in this plan) adds custom dev tool plugins (GitHub, git, project switcher).

(see brainstorm: `docs/brainstorms/2026-03-02-raycast-ux-linux-brainstorm.md`)

## Problem Statement / Motivation

The current launcher setup uses rofi exclusively. While rofi handles app launching and clipboard well, it operates as isolated modes — the user must know which mode to invoke (`SUPER+D` for apps, `SUPER+C` for clipboard). There is no unified "search everything" interface. Missing entirely: calculator, emoji picker, file browser, window switcher, websearch, SSH quick-connect, and system commands — all available from a single hotkey in Raycast.

## Proposed Solution

Hybrid approach: Walker as the primary command palette (`SUPER+Space`), rofi retained as fallback (`SUPER+D`). Walker runs as a systemd user service (daemon mode) for instant response. Rofi is untouched — existing bindings continue working. The wallpaper picker (`SUPER+W`) remains on rofi permanently since it uses rofi's custom script-modi protocol.

### Clipboard Transition Plan

Three explicit states:
1. **Initial deploy:** Both cliphist and Walker's clipboard run simultaneously. `SUPER+C` still uses cliphist+rofi. Walker's `:` prefix also works.
2. **Evaluation (1-2 weeks):** User tests Walker clipboard reliability. If issues arise, cliphist is the fallback.
3. **Migration:** Remove cliphist `exec-once` lines. Rebind `SUPER+C` to `walker` (or remove it — user just uses `SUPER+Space` then `:`). cliphist package stays installed for rollback.

## Technical Approach

### Architecture

```
SUPER+Space ──► Walker (systemd service)
                  ├── elephant daemon (data provider, systemd service)
                  │     ├── Applications (freedesktop .desktop)
                  │     ├── Calculator (built-in)
                  │     ├── Clipboard (own wl-paste watcher)
                  │     ├── Symbols/Emoji
                  │     ├── Files (indexer)
                  │     ├── Windows (Hyprland IPC)
                  │     ├── Websearch (→ Firefox)
                  │     ├── SSH (parses ~/.ssh/config + known_hosts)
                  │     ├── Bluetooth
                  │     └── Runner (shell commands)
                  └── GTK4 layer-shell UI (Tokyo Night CSS theme)

SUPER+D ────► Rofi (unchanged, Stylix-themed)
SUPER+C ────► cliphist + rofi (kept during evaluation)
SUPER+W ────► Rofi wallpaper picker (permanent)
```

### Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `flake.nix` | Modify | Add Walker flake input |
| `modules/shared/nix.nix` | Modify | Add Cachix substituters |
| `home/linux/walker.nix` | Create | Walker home-manager config + theme |
| `home/linux/default.nix` | Modify | Import walker.nix |
| `home/linux/hyprland.nix` | Modify | Add `SUPER+Space` bind |

### Implementation Phases

#### Phase 1a: Flake Input and Cachix

**Tasks:**
- Add Walker flake input to `flake.nix` (line ~29, before closing `};`)
- Add `walker` to outputs destructuring (line 32)
- Add Walker Cachix URLs to `modules/shared/nix.nix` substituters/keys lists

**Files:**

`flake.nix` — add input:
```nix
walker = {
  url = "github:abenz1267/walker";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

`flake.nix` — add to outputs destructuring:
```nix
outputs = { self, nixpkgs, nixpkgs-unstable, home-manager, nixos-hardware, disko, lanzaboote, stylix, walker, ... }@inputs:
```

`modules/shared/nix.nix` — extend substituters and keys:
```nix
substituters = [
  "https://cache.nixos.org"
  "https://nix-community.cachix.org"
  "https://walker.cachix.org"
  "https://walker-git.cachix.org"
];
trusted-public-keys = [
  "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
  "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
  "walker.cachix.org-1:fG8q+uAaMqhsMxWjwvk0IMb4mFPFLqHjuvfwQxE4oJM="
  "walker-git.cachix.org-1:vmC0ocfPWh0S/vRAQGtChuiZBTAe4wiKDeyyXM0/7pM="
];
```

**Success criteria:** `nix flake check` passes. Walker input resolves.

#### Phase 1b: Walker Home-Manager Module

**Tasks:**
- Create `home/linux/walker.nix` with Walker config, modules, and Tokyo Night theme
- Import Walker's home-manager module from the flake input
- Enable `runAsService = true` for systemd-managed daemon
- Configure all core modules with prefix bindings
- Write Tokyo Night Dark CSS theme inline

**File: `home/linux/walker.nix`**

```nix
{ inputs, config, ... }:
{
  imports = [ inputs.walker.homeManagerModules.walker ];

  programs.walker = {
    enable = true;
    runAsService = true;

    config = {
      close_when_open = true;
      click_to_close = true;
      single_click_activation = true;
      theme = "tokyo-night";
      as_window = false;

      shell = {
        layer = "overlay";
        anchor_top = true;
        anchor_bottom = true;
        anchor_left = true;
        anchor_right = true;
      };

      placeholders."default" = {
        input = "Search...";
        list = "No Results";
      };

      keybinds = {
        close = [ "Escape" ];
        next = [ "Down" ];
        previous = [ "Up" ];
      };

      providers = {
        default = [ "desktopapplications" "calc" "websearch" ];
        empty = [ "desktopapplications" ];
        max_results = 50;

        prefixes = [
          { prefix = ";"; provider = "providerlist"; }
          { prefix = ">"; provider = "runner"; }
          { prefix = "/"; provider = "files"; }
          { prefix = "."; provider = "symbols"; }
          { prefix = "="; provider = "calc"; }
          { prefix = "@"; provider = "websearch"; }
          { prefix = ":"; provider = "clipboard"; }
          { prefix = "$"; provider = "windows"; }
        ];
      };
    };

    themes."tokyo-night" = {
      style = ''
        /* Tokyo Night Dark — base16 colors from Stylix */
        @define-color bg #1a1b26;
        @define-color bg_light #16161e;
        @define-color selection #2f3549;
        @define-color comment #444b6a;
        @define-color fg_dim #787c99;
        @define-color fg #a9b1d6;
        @define-color fg_light #cbccd1;
        @define-color accent #7aa2f7;
        @define-color green #9ece6a;
        @define-color cyan #b4f9f8;
        @define-color blue #2ac3de;
        @define-color purple #bb9af7;
        @define-color red #f7768e;

        .box-wrapper {
          background: @bg;
          border: 1px solid alpha(@accent, 0.3);
          border-radius: 16px;
          padding: 16px;
          box-shadow: 0 8px 32px alpha(black, 0.4);
        }

        .input {
          background: @bg_light;
          padding: 12px 16px;
          border-radius: 8px;
          border: 1px solid @selection;
          color: @fg;
          caret-color: @accent;
          font-family: "Noto Sans", sans-serif;
          font-size: 16px;
        }

        .input:focus {
          border-color: alpha(@accent, 0.5);
        }

        .list {
          margin-top: 8px;
        }

        .item-box {
          border-radius: 8px;
          padding: 8px 12px;
          color: @fg;
        }

        child:selected .item-box,
        row:selected .item-box {
          background: alpha(@accent, 0.15);
        }

        .item-text {
          font-family: "Noto Sans", sans-serif;
          font-size: 14px;
          color: @fg;
        }

        .item-subtext {
          font-family: "Noto Sans", sans-serif;
          font-size: 12px;
          color: @fg_dim;
        }

        .item-image {
          margin-right: 8px;
        }

        .item-quick-activation {
          font-family: "JetBrainsMono Nerd Font", monospace;
          font-size: 11px;
          color: @comment;
          background: @selection;
          border-radius: 4px;
          padding: 2px 6px;
        }

        .placeholder {
          color: @comment;
          font-style: italic;
        }

        .keybinds {
          margin-top: 8px;
          padding-top: 8px;
          border-top: 1px solid @selection;
        }

        .keybind-label {
          color: @fg_dim;
          font-size: 11px;
        }

        .keybind-bind {
          color: @accent;
          font-family: "JetBrainsMono Nerd Font", monospace;
          font-size: 11px;
        }

        .error {
          color: @red;
        }

        .calc .item-text {
          color: @green;
          font-family: "JetBrainsMono Nerd Font", monospace;
        }

        .symbols .item-image-text {
          font-size: 24px;
        }

        .elephant-hint {
          color: @comment;
          font-size: 12px;
        }
      '';
    };
  };
}
```

**Success criteria:** `nixos-rebuild dry-build` passes with Walker module.

#### Phase 1c: Integration — Imports and Keybinding

**Tasks:**
- Add `./walker.nix` to `home/linux/default.nix` imports
- Add `SUPER+Space` keybinding to `home/linux/hyprland.nix`

`home/linux/default.nix`:
```nix
imports = [
  ./desktop.nix
  ./hyprlock.nix
  ./wlogout.nix
  ./waybar.nix
  ./rofi.nix
  ./swaync.nix
  ./starship.nix
  ./wallpaper.nix
  ./walker.nix        # NEW
];
```

`home/linux/hyprland.nix` — add to `bind` list:
```nix
"$mod, SPACE, exec, walker"
```

**Success criteria:** Full `bash apps/build-switch` succeeds. `SUPER+Space` opens Walker.

#### Phase 1d: Verification and Testing

**Tasks:**
- Rebuild system with `bash apps/build-switch`
- Verify `systemctl --user status walker.service` is active
- Verify `systemctl --user status elephant.service` is active
- Test `SUPER+Space` opens Walker
- Test app search (type an app name)
- Test `=` prefix (calculator)
- Test `:` prefix (clipboard — should show history)
- Test `.` prefix (symbols/emoji)
- Test `/` prefix (file browser)
- Test `$` prefix (window switcher — lists open windows)
- Test `@` prefix (websearch — opens Firefox)
- Test `>` prefix (runner — executes shell command)
- Verify `SUPER+D` still opens rofi
- Verify `SUPER+C` still opens cliphist via rofi
- Verify `SUPER+W` still opens wallpaper picker
- Verify Walker does NOT open when hyprlock is active
- Test Walker on both monitors (should appear on focused monitor)

**Success criteria:** All modules respond to their prefixes. Rofi bindings unaffected. No layer-shell conflicts.

## System-Wide Impact

- **Interaction graph:** `SUPER+Space` → Hyprland bind → `walker` binary → IPC to `elephant.service` (systemd) → results displayed as GTK4 layer-shell. Selection triggers app launch / clipboard copy / browser open / window focus via Hyprland IPC.
- **Error propagation:** If elephant crashes, Walker shows no results. systemd `Restart=on-failure` should auto-recover. If Walker binary crashes, the keybind does nothing until service restarts.
- **State lifecycle risks:** Clipboard history lives in elephant's data store (not cliphist). If elephant's database corrupts, clipboard history is lost. No migration from cliphist history — clean start.
- **API surface parity:** `SUPER+C` (cliphist+rofi) and Walker's `:` prefix both provide clipboard access during evaluation. After migration, only Walker remains.

## Acceptance Criteria

### Functional Requirements

- [ ] `SUPER+Space` opens Walker command palette instantly (daemon mode)
- [ ] App search works with frecency (recently used apps ranked higher)
- [ ] `=` prefix triggers calculator with result copy-to-clipboard
- [ ] `:` prefix shows clipboard history (text and images)
- [ ] `.` prefix opens symbol/emoji picker
- [ ] `/` prefix opens file browser from home directory
- [ ] `$` prefix lists open windows across all workspaces, selecting switches focus
- [ ] `@` prefix triggers websearch, opening results in Firefox
- [ ] `>` prefix runs shell commands
- [ ] `Escape` dismisses Walker
- [ ] `SUPER+D` still opens rofi app launcher
- [ ] `SUPER+C` still opens cliphist+rofi clipboard
- [ ] `SUPER+W` still opens rofi wallpaper picker
- [ ] Walker does not open while hyprlock is active

### Non-Functional Requirements

- [ ] Walker opens in <100ms (daemon mode)
- [ ] Walker theme matches Tokyo Night Dark palette (consistent with rest of desktop)
- [ ] Fonts match Stylix config (Noto Sans for UI, JetBrainsMono NF for monospace)
- [ ] `nixos-rebuild dry-build` passes before applying
- [ ] systemd services auto-restart on failure

## Dependencies & Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Walker flake API changes | Medium | Medium | Pin to specific commit after initial integration works |
| Clipboard conflict (cliphist + elephant) | Medium | Low | Both run during eval; remove cliphist only after testing |
| Walker crashes on Hyprland update | Low | Low | Rofi fallback is untouched; `SUPER+D` always works |
| Elephant daemon fails to start | Low | Medium | systemd auto-restart; `systemctl --user status elephant` for diagnostics |
| Theme drift from Stylix | Low | Low | Colors are hardcoded from same base16 scheme; update CSS if scheme changes |
| Single-maintainer project risk | Medium | Medium | Rofi fallback means Walker can be removed cleanly (see rollback plan in brainstorm) |

## Rollback Plan

(see brainstorm: `docs/brainstorms/2026-03-02-raycast-ux-linux-brainstorm.md` — Rollback Plan section)

1. Remove `walker.nix` import from `home/linux/default.nix`
2. Remove Walker flake input from `flake.nix`
3. Remove `SUPER+Space` bind from `home/linux/hyprland.nix`
4. Remove Cachix entries from `modules/shared/nix.nix`
5. Re-enable cliphist `exec-once` lines if they were removed
6. `bash apps/build-switch` — system returns to pre-Walker state
7. Zero impact on existing rofi workflow

## Sources & References

### Origin

- **Brainstorm document:** [docs/brainstorms/2026-03-02-raycast-ux-linux-brainstorm.md](docs/brainstorms/2026-03-02-raycast-ux-linux-brainstorm.md) — Key decisions carried forward: hybrid Walker+rofi approach, two-phase rollout, Cachix trust, AI module skipped

### Internal References

- Flake inputs pattern: `flake.nix:4-30`
- specialArgs/extraSpecialArgs: `flake.nix:44,72`
- Hyprland keybindings: `home/linux/hyprland.nix:50-86`
- cliphist exec-once: `home/linux/hyprland.nix:38-39`
- Rofi config: `home/linux/rofi.nix`
- Stylix config: `modules/nixos/stylix.nix`
- Cachix settings: `modules/shared/nix.nix:12-19`
- Linux module imports: `home/linux/default.nix`

### External References

- [Walker GitHub](https://github.com/abenz1267/walker)
- [Elephant GitHub](https://github.com/abenz1267/elephant)
- [Walker official site](https://walkerlauncher.com/)
- Walker Cachix: `walker.cachix.org`, `walker-git.cachix.org`
