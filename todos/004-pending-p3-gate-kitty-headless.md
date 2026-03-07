---
status: pending
priority: p3
issue_id: "004"
tags: [home-manager, headless, do-nixbox, optimization]
dependencies: ["do-nixbox host deployed"]
---

# Gate kitty.nix Behind Headless Flag

## Problem Statement

`home/common/kitty.nix` installs the kitty GUI terminal emulator (~150 MB closure) on all hosts including headless servers where it will never be used. `home/common/fastfetch.nix` also references `kitty-direct` logo rendering which does not work over SSH.

## Proposed Solution

In `home/common/default.nix` (or wherever kitty is imported), wrap the kitty import with `lib.optionals (!headless)`. Optionally adjust fastfetch logo type when headless.

## Acceptance Criteria

- [ ] kitty is not installed on do-nixbox
- [ ] kitty is still installed on thinkpad and macbook-pro
- [ ] fastfetch works on do-nixbox (graceful fallback if kitty-direct unavailable)

## Technical Details

- **Affected files:** `home/common/default.nix`, possibly `home/common/fastfetch.nix`
- **Origin:** Identified during do-nixbox planning
