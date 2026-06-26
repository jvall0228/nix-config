---
status: resolved
priority: p3
issue_id: "004"
tags: [home-manager, headless, do-nixbox, optimization]
dependencies: ["do-nixbox host deployed"]
---

# Gate kitty.nix Behind Headless Flag

## Problem Statement

`home/common/kitty.nix` installs the kitty GUI terminal emulator (~150 MB closure) on all hosts including headless servers where it will never be used. `home/common/fastfetch.nix` also references `kitty-direct` logo rendering which does not work over SSH.

## Resolution (2026-06-26)

- `home/default.nix`: moved `./common/kitty.nix` out of the unconditional
  imports into a `lib.optionals (!headless)` group, so kitty is dropped on
  headless hosts but kept on thinkpad (Linux desktop) and macbook-pro (Darwin).
- `home/common/fastfetch.nix`: now takes `headless ? false` and selects the
  built-in distro logo (`type = "builtin"`) over SSH instead of `kitty-direct`,
  which needs the kitty graphics protocol unavailable in a headless session.

## Acceptance Criteria

- [x] kitty is not installed on do-nixbox (`programs.kitty.enable` → false)
- [x] kitty is still installed on thinkpad and macbook-pro (`programs.kitty.enable` → true)
- [x] fastfetch works on do-nixbox (uses built-in logo; no kitty-direct dependency)

## Technical Details

- **Affected files:** `home/default.nix`, `home/common/fastfetch.nix`
- **Verified:** `nix eval` confirms per-host `programs.kitty.enable` and the
  fastfetch logo type; `do-nixbox` dry-build passes.
- **Origin:** Identified during do-nixbox planning
