---
status: pending
priority: p2
issue_id: "001"
tags: [nvidia, power-management, battery, fix/suspend-resume]
dependencies: []
---

# NVIDIA GPU Runtime PM Stuck on "forbidden"

## Problem Statement

After switching to PRIME offload with finegrained power management (`fix/suspend-resume` branch, PR #6), the NVIDIA RTX A2000 GPU stays powered on even when idle. The runtime PM status reads `active` and `runtime_enabled` reads `forbidden`, meaning no process has set `power/control` to `auto` for the device.

This means the dGPU draws power continuously, reducing battery life. The GPU should suspend itself when no clients are using it.

## Findings

- `cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status` returns `active`
- `cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_enabled` returns `forbidden`
- `cat /sys/bus/pci/devices/0000:01:00.0/power/control` is implicitly `on` (always on)
- `DynamicPowerManagement: 3` is set in `/proc/driver/nvidia/params` (correct for fine-grained)
- TLP config has `RUNTIME_PM_DRIVER_DENYLIST="nvidia"` which tells TLP to skip the nvidia device
- NixOS `hardware.nvidia.powerManagement.finegrained = true` should create udev rules to write `auto` to `power/control`

**Root cause hypothesis:** The TLP denylist and the NixOS finegrained udev rule may be conflicting. TLP runs after udev and may be resetting `power/control` back to `on` because it doesn't see nvidia in its "allowed" list — or the udev rule from NixOS finegrained isn't firing at all.

## Proposed Solutions

### Option A: Remove TLP denylist, let NixOS udev handle everything
- **Change:** Remove `RUNTIME_PM_DRIVER_DENYLIST = "nvidia"` from `modules/nixos/power.nix`
- **Pros:** Simplest fix; NixOS finegrained option is designed to handle this end-to-end
- **Cons:** TLP might then also try to manage nvidia runtime PM, causing double-management
- **Effort:** Small
- **Risk:** Low

### Option B: Add explicit udev rule to force `power/control = auto`
- **Change:** Add a udev rule in `modules/nixos/nvidia.nix` that writes `auto` to the NVIDIA device's `power/control`
- **Pros:** Explicit, doesn't depend on NixOS finegrained udev internals
- **Cons:** Duplicates what finegrained should already do
- **Effort:** Small
- **Risk:** Low

### Option C: Debug the NixOS finegrained udev rule
- **Change:** Inspect what udev rules NixOS actually generates for `powerManagement.finegrained = true`, verify they match the PCI device, check rule ordering vs TLP
- **Pros:** Fixes the root cause rather than working around it
- **Cons:** Requires deeper investigation
- **Effort:** Medium
- **Risk:** None (investigation only)

## Recommended Action

Start with Option C to understand the root cause, then apply Option A or B as needed.

## Technical Details

- **Affected files:** `modules/nixos/nvidia.nix`, `modules/nixos/power.nix`
- **Branch:** `fix/suspend-resume` (PR #6)
- **Device:** NVIDIA RTX A2000 Laptop GPU at PCI `0000:01:00.0`
- **NixOS options:** `hardware.nvidia.powerManagement.finegrained`, `services.tlp.settings.RUNTIME_PM_DRIVER_DENYLIST`

## Acceptance Criteria

- [ ] `cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_enabled` returns `enabled`
- [ ] `cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status` returns `suspended` after 30s idle
- [ ] Battery drain at idle is measurably reduced vs current state
- [ ] Suspend/resume still works correctly after fix

## Work Log

| Date | Action | Result |
|---|---|---|
| 2026-03-03 | Discovered during post-rebuild testing of PR #6 | GPU runtime PM `forbidden`, stays `active` |
| 2026-03-03 | Verified PRIME offload otherwise works (AMD is default renderer, env vars unset) | 7/8 tests pass |

## Resources

- PR #6: fix/suspend-resume
- [NixOS NVIDIA wiki](https://nixos.wiki/wiki/NVIDIA)
- [NVIDIA Dynamic Power Management docs](https://download.nvidia.com/XFree86/Linux-x86_64/latest/README/dynamicpowermanagement.html)
