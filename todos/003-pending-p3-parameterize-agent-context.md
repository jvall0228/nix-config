---
status: pending
priority: p3
issue_id: "003"
tags: [agent-context, multi-host, shellbox]
dependencies: ["shellbox host deployed"]
---

# Parameterize agent-context.nix for Multi-Host Accuracy

## Problem Statement

`modules/nixos/agent-context.nix` has a hardcoded `enabledModules` list (lines 8-17) and thinkpad-specific content (Hyprland paths, Lanzaboote generation limit, sbctl references). When used on shellbox, `/etc/agent-context.md` contains misleading information about the system.

## Proposed Solution

Make `enabledModules` dynamic by either:
- Accepting it as a module argument / specialArgs value set per-host in `flake.nix`
- Auto-detecting enabled modules from `config` attributes (e.g., check `config.services.xserver.enable`, `config.hardware.nvidia.enable`, etc.)

Also conditionally include/exclude sections like "Desktop/Hyprland" and "Lanzaboote" based on what's actually enabled.

## Acceptance Criteria

- [ ] `/etc/agent-context.md` on shellbox accurately reflects its module set
- [ ] `/etc/agent-context.md` on thinkpad is unchanged
- [ ] No hardcoded host-specific content in `agent-context.nix`

## Technical Details

- **Affected file:** `modules/nixos/agent-context.nix`
- **Origin:** Identified during shellbox planning (see `docs/plans/2026-03-05-feat-shellbox-digitalocean-host-plan.md`)
