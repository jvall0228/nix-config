---
title: "fix: Suspend/Resume Freeze on Hybrid GPU Laptop"
type: fix
status: completed
date: 2026-03-02
origin: docs/brainstorms/2026-03-02-suspend-resume-fix-brainstorm.md
---

# fix: Suspend/Resume Freeze on Hybrid GPU Laptop

## Overview

After hypridle triggers `systemctl suspend` (15-minute idle timeout), waking the laptop produces a black screen with a blinking cursor and a completely unresponsive keyboard, requiring a hard reboot every time.

## Problem Statement

The NVIDIA discrete GPU (RTX A2000 Mobile) is configured as the **sole primary renderer** on a hybrid AMD+NVIDIA laptop. Session variables (`GBM_BACKEND=nvidia-drm`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, `LIBVA_DRIVER_NAME=nvidia`) force all rendering through NVIDIA. On suspend, the NVIDIA driver fails to properly restore the display pipeline, hanging the GPU and freezing the system.

Additionally, `kernel.sysrq = 0` prevents any keyboard-based recovery, making every failed resume require a hard power-off.

## Proposed Solution

Switch to **PRIME offload mode**: AMD Radeon 680M (iGPU) handles all display output; NVIDIA RTX A2000 Mobile (dGPU) activates only on-demand via `nvidia-offload` wrapper for CUDA/gaming workloads. Enable NVIDIA finegrained power management for proper dGPU suspend/resume cycling (see brainstorm: `docs/brainstorms/2026-03-02-suspend-resume-fix-brainstorm.md`).

### Hardware verification (performed during planning)

- **All display connectors (eDP-1, HDMI-A-1, DP-1 through DP-5) are wired to card2 (AMD amdgpu)** — no reverse sync needed
- NVIDIA (card1, vendor `0x10de`) has **zero display outputs**
- `NVreg_PreserveVideoMemoryAllocations=1` is **already present** in kernel cmdline via `powerManagement.enable = true` — no manual kernel param needed

## Technical Considerations

### TLP and finegrained PM interaction

`power.nix` sets `RUNTIME_PM_ON_BAT = "auto"` via TLP. When `powerManagement.finegrained = true` is enabled, both TLP and the NVIDIA driver attempt to manage PCI runtime PM for the dGPU. Add `RUNTIME_PM_DRIVER_DENYLIST = "nvidia"` to TLP config to prevent conflicts.

### nixos-hardware nonprime module

`flake.nix` line 62 imports `nixos-hardware.nixosModules.common-gpu-nvidia-nonprime`. This module only sets `services.xserver.videoDrivers = lib.mkDefault [ "nvidia" ]`, which is already explicitly set in `nvidia.nix`. Remove it — it's semantically incorrect for a PRIME offload setup and could cause confusion.

### WLR_NO_HARDWARE_CURSORS

Currently set in `nvidia.nix`. With AMD as primary GPU, hardware cursors work natively. Keep it initially for safety; remove as a follow-up cleanup if cursors work fine.

### Hyprland GPU auto-detection

No `AQ_DRM_DEVICES` is set. Hyprland/Aquamarine should auto-detect AMD (card2) as primary since all display connectors are on it. If Hyprland still picks NVIDIA, add `AQ_DRM_DEVICES,/dev/dri/card2:/dev/dri/card1` to hyprland.nix env block as a fallback.

### Hibernation

Out of scope. The 16GB swap is hibernation-ready, but this fix targets S3 suspend only.

## Acceptance Criteria

- [ ] System successfully idle-suspends and resumes to a working hyprlock screen (5+ consecutive cycles)
- [ ] `hyprctl dispatch dpms on && wallpaper-restore` (after_sleep_cmd) works on resume
- [ ] `nvidia-offload` wrapper is available and functional (e.g., `nvidia-offload glxinfo | grep NVIDIA`)
- [ ] No NVIDIA-forcing session variables remain (`env | grep -i nvidia` shows no `GBM_BACKEND`, `__GLX_VENDOR_LIBRARY_NAME`, or `LIBVA_DRIVER_NAME`)
- [ ] AMD iGPU is the active display renderer (`cat /sys/class/drm/card2/device/driver` → `amdgpu`)
- [ ] Hardware video decoding works via AMD VA-API (`vainfo` shows radeonsi)
- [ ] System builds cleanly with `nixos-rebuild test` before `switch`

## Changes Required

### 1. `modules/nixos/nvidia.nix`

Add PRIME offload configuration, finegrained PM, and remove NVIDIA-as-primary session variables:

```nix
{ config, ... }:
{
  hardware.nvidia = {
    modesetting.enable = true;
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    powerManagement.enable = true;
    powerManagement.finegrained = true;

    prime = {
      offload = {
        enable = true;
        enableOffloadCmd = true;  # provides nvidia-offload wrapper
      };
      amdgpuBusId = "PCI:102:0:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  hardware.graphics.enable = true;
  services.xserver.videoDrivers = [ "nvidia" ];

  environment.sessionVariables = {
    WLR_NO_HARDWARE_CURSORS = "1";  # keep initially; remove later if AMD cursors work
  };
}
```

**Removed:** `LIBVA_DRIVER_NAME`, `__GLX_VENDOR_LIBRARY_NAME`, `GBM_BACKEND` — these force NVIDIA as primary renderer, conflicting with PRIME offload (see brainstorm: decision #3).

**Added:** `prime.offload`, bus IDs, `finegrained = true` (see brainstorm: decisions #1, #2).

### 2. `modules/nixos/core.nix`

Change SysRq from disabled to safe subset for GPU hang recovery:

```nix
# Change:
boot.kernel.sysctl."kernel.sysrq" = 0;
# To:
boot.kernel.sysctl."kernel.sysrq" = 176;
```

Value `176` enables: sync (16) + remount-readonly (32) + reboot (128) + term/kill signals. Sufficient for recovering from GPU hangs without exposing memory dumps, maintaining the existing kernel hardening posture (see brainstorm: decision #4).

**NOT adding** `NVreg_PreserveVideoMemoryAllocations=1` to `boot.kernelParams` — verified it is already set automatically by `powerManagement.enable = true` (confirmed via `/proc/cmdline`).

### 3. `flake.nix`

Remove the nonprime hardware module:

```nix
# Remove this line (~line 62):
nixos-hardware.nixosModules.common-gpu-nvidia-nonprime
```

This module only sets `services.xserver.videoDrivers = lib.mkDefault [ "nvidia" ]`, already covered by `nvidia.nix`. Semantically incorrect for a PRIME offload setup.

### 4. `modules/nixos/power.nix`

Add NVIDIA to TLP's runtime PM denylist to prevent conflicts with finegrained PM:

```nix
RUNTIME_PM_DRIVER_DENYLIST = "nvidia";
```

### 5. `home/linux/hyprlock.nix` — Verify only

Confirm `after_sleep_cmd = "hyprctl dispatch dpms on && wallpaper-restore"` still works. No changes expected — the command targets Hyprland/DPMS, not GPU-specific APIs.

## Dependencies & Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| New config fails to boot | High | Use `nixos-rebuild test` first (applies without boot entry), then `switch` |
| Hyprland picks NVIDIA as primary despite PRIME offload | Medium | Add `AQ_DRM_DEVICES` to hyprland.nix env block as fallback |
| Lanzaboote 10-generation limit | Low | Test before switch; rollback with `sudo nixos-rebuild switch --rollback` |
| Video wallpaper (mpvpaper) broken after resume | Low | Accept current behavior; wallpaper issues are a separate fix |

## Testing Protocol

1. `nixos-rebuild test --flake ~/nix-config#thinkpad` — apply without boot entry
2. Verify `env | grep -i nvidia` shows no forcing variables
3. Verify `nvidia-offload glxinfo | grep NVIDIA` works
4. Trigger idle suspend → resume → unlock hyprlock (repeat 3-5 times)
5. If stable: `nixos-rebuild switch --flake ~/nix-config#thinkpad`

## Sources & References

- **Origin brainstorm:** [docs/brainstorms/2026-03-02-suspend-resume-fix-brainstorm.md](docs/brainstorms/2026-03-02-suspend-resume-fix-brainstorm.md) — Key decisions carried forward: PRIME offload mode, finegrained PM, session variable removal, SysRq enablement, nvidia-offload wrapper
- Hardware verification: `/sys/class/drm/card*/` and `/proc/cmdline` inspected during planning
- `common-gpu-nvidia-nonprime` module: [NixOS/nixos-hardware flake.nix](https://github.com/NixOS/nixos-hardware/blob/master/flake.nix)
- NixOS NVIDIA wiki: [wiki.nixos.org/wiki/NVIDIA](https://wiki.nixos.org/wiki/NVIDIA)
