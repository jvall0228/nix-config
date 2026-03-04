# Brainstorm: Raycast-Like UX on NixOS/Hyprland

**Date:** 2026-03-02
**Status:** Decided

## What We're Building

A Raycast-like unified command palette experience on NixOS/Hyprland using **Walker** as the primary launcher alongside the existing **rofi** as a fallback. The goal is a single hotkey (`SUPER+Space`) that opens an instant, searchable interface for launching apps, running calculations, browsing clipboard history, picking emoji, searching files, switching windows, managing system settings, and running custom dev scripts.

## Why This Approach (Hybrid: Walker + Rofi)

**Walker** is the closest Linux equivalent to Raycast — it was designed to be exactly that. It provides:

- Prefix-based module activation (`=` calc, `/` files, `:` clipboard, `.` symbols) mirroring Raycast's command system
- Daemon mode ("elephant") for near-instant popup after first launch
- 14+ built-in modules covering apps, clipboard, calculator, file browser, window switcher, AI chat, websearch, SSH, bluetooth, bookmarks
- Custom plugin support via simple stdin/stdout scripts (same difficulty as rofi)

**Keeping rofi** alongside Walker provides a safety net:

- Rofi is battle-tested, Stylix auto-themed, and already configured
- If Walker breaks after a NixOS update or the single-maintainer project stalls, the fallback is ready
- Existing rofi bindings (`SUPER+D` for apps, `SUPER+C` for clipboard) continue working during evaluation
- Once confidence in Walker is established, rofi can be dropped entirely

### Why Not the Alternatives

- **Rofi-only command palace:** Fundamental UX is "pick a mode, then search" — can't match Walker's seamless prefix system. Would require significant custom scripting for a worse result.
- **Anyrun:** Missing clipboard history, file browser, and Hyprland window switcher. Custom plugins require Rust `.so` files (high barrier). Not trying to be Raycast.
- **Walker all-in:** Risky given single maintainer, ancient nixpkgs version requiring flake input, and no Stylix target. Hybrid approach mitigates these risks.

## Key Decisions

1. **Hybrid approach:** Walker as primary command palette (`SUPER+Space`), rofi as fallback (`SUPER+D`)
2. **Two-phase rollout:** Core modules first (apps, calc, clipboard, emoji, files, windows, system). Dev tool plugins (GitHub, git, project switcher) are a follow-up after core is stable.
3. **Walker via flake input:** nixpkgs version (0.13) is too old; need upstream flake (`github:abenz1267/walker`) for v2.14+
4. **Cachix binary cache:** Trust `walker.cachix.org` for pre-built binaries to avoid long Rust builds
5. **Manual theming:** Tokyo Night Dark CSS for Walker since Stylix has no Walker target
6. **AI module skipped:** Walker's built-in Claude/Gemini chat requires API keys (no OAuth support). Skip — Claude Code in terminal is sufficient.
7. **Custom dev plugins (Phase 2):** GitHub PRs/issues, git status, project switcher via stdin/stdout scripts (not Rust)

## Modules to Enable

### Core Essentials
- **Applications** — with frecency/history awareness
- **Calculator** — `=` prefix, unit conversions
- **Clipboard** — `:` prefix, via elephant daemon (replaces `SUPER+C` cliphist binding over time)
- **Symbols/Emoji** — `.` prefix
- **File Browser** — `/` prefix
- **Window Switcher** — Hyprland-native window list

### System Controls
- **Websearch** — configurable search engines
- **SSH** — parses known_hosts and config
- **Bluetooth** — management interface
- **Power/Session** — lock, logout, suspend, reboot, shutdown (custom script)

### Dev Tools — Phase 2 (Custom stdin/stdout Plugins)
- **GitHub** — list PRs/issues, open in browser
- **Git Status** — show current branch, changed files
- **Project Switcher** — quick-open projects in editor

## Keybinding Plan

| Binding | Action | Tool |
|---------|--------|------|
| `SUPER+Space` | Walker command palette (NEW) | Walker |
| `SUPER+D` | Quick app launch (KEEP) | Rofi |
| `SUPER+C` | Clipboard history (KEEP, evaluate replacing with Walker) | Rofi/cliphist |
| `SUPER+W` | Wallpaper picker (KEEP) | Rofi |

## Open Questions

1. **Walker flake module type:** Does the upstream flake provide a home-manager module, NixOS module, or both? How is the elephant daemon managed (systemd user service)?
2. **Clipboard coexistence:** Walker's clipboard daemon and cliphist both watch `wl-paste`. Do they conflict? Plan: test running both, disable cliphist if Walker clipboard works reliably.
3. **Walker CSS location:** Where should the theme CSS live in the Nix config — inline in a home-manager module via `xdg.configFile`, or as a separate file in the repo?

## Resolved Questions

- **Cachix:** Yes, trust `walker.cachix.org` for pre-built binaries.
- **Dev tools timing:** Phase 2 — get core working first.
- **AI module:** Skip — requires API keys, no OAuth, Claude Code in terminal is sufficient.

## Rollback Plan

If Walker causes issues (crashes, Hyprland conflicts, abandoned upstream):
1. Remove Walker flake input and home-manager config
2. Rofi is untouched and continues working on `SUPER+D` and `SUPER+C`
3. Re-enable cliphist `exec-once` if it was disabled
4. Remove `SUPER+Space` binding
5. Zero impact on existing workflow

## Technical Notes

- Walker requires the `elephant` daemon service for clipboard history and service mode
- Walker flake provides both NixOS and home-manager modules
- Binary cache available at `walker.cachix.org` to avoid long Rust builds
- Custom plugins follow stdin/stdout protocol — write a script that prints options, reads selection
- Rofi's wallpaper picker (custom script-modi) stays on rofi — no need to migrate this
