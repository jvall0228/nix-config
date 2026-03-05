---
status: pending
priority: p2
issue_id: "002"
tags: [refactor, core, multi-host, shellbox]
dependencies: ["shellbox host deployed"]
---

# Refactor core.nix into Shared and Workstation Modules

## Problem Statement

`modules/nixos/core.nix` was written for the thinkpad (a desktop/laptop) and is now shared with shellbox (a headless server). Several settings are workstation-specific and require `mkForce` overrides in `hosts/shellbox/default.nix`:

- Syncthing firewall ports (TCP 22000, UDP 22000/21027)
- NetworkManager with WiFi MAC randomization
- `sbctl` package (secure boot tool, irrelevant on BIOS/GRUB)
- `quiet` / `loglevel=3` boot params (suppress logs, bad for server debugging)
- User groups include `video` and `networkmanager` (unnecessary on headless)

As more hosts are added, these overrides will multiply and drift.

## Proposed Solution

Split `modules/nixos/core.nix` into:

- **`modules/nixos/core.nix`** — Shared base: kernel hardening, sysctl, firewall (enabled, no ports), locale, timezone, sudo, user creation, auto-upgrade, base packages
- **`modules/nixos/workstation.nix`** — Desktop additions: NetworkManager WiFi config, Syncthing ports, `sbctl`, quiet boot, video group

Thinkpad imports both. Shellbox imports only `core.nix`.

## Acceptance Criteria

- [ ] `modules/nixos/core.nix` contains only host-agnostic settings
- [ ] `modules/nixos/workstation.nix` contains desktop/laptop-specific settings
- [ ] Thinkpad flake modules list includes both `core.nix` and `workstation.nix`
- [ ] Shellbox flake modules list includes only `core.nix`
- [ ] All `mkForce` overrides in `hosts/shellbox/default.nix` are removed (no longer needed)
- [ ] Both hosts build and pass checks

## Technical Details

- **Affected files:** `modules/nixos/core.nix`, `flake.nix`, `hosts/shellbox/default.nix`
- **New file:** `modules/nixos/workstation.nix`
- **Origin:** Identified during shellbox planning (see `docs/plans/2026-03-05-feat-shellbox-digitalocean-host-plan.md`)
