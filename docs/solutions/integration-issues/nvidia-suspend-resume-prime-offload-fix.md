---
title: "ThinkPad P15v Gen 3 Suspend/Resume Freeze — Root Cause & Resolution"
date: 2026-03-03
status: documented
category: integration-issues
tags:
  - suspend
  - resume
  - nvidia
  - prime
  - s2idle
  - s0ix
  - firmware-limitation
  - power-management
  - hyprland
severity: critical
component: modules/nixos/nvidia.nix, modules/nixos/power.nix, home/linux/hyprlock.nix, home/linux/wlogout.nix
symptoms: |
  After idle suspend, laptop freezes on resume with black screen, blinking cursor, and unresponsive keyboard.
  Requires hard reboot to recover. Occurs consistently across multiple suspend cycles.
root_cause: |
  Hardware firmware only supports s2idle (S0ix/modern standby), NOT S3 deep sleep. NVIDIA driver 580.x
  cannot properly handle s2idle suspend/resume cycles, hanging the GPU during resume.
resolution_type: workaround-disable
---

# ThinkPad P15v Gen 3 Suspend/Resume Freeze

## Symptom

After hypridle triggers `systemctl suspend` (15-minute idle timeout), waking the laptop produces a black screen with a blinking cursor and a completely unresponsive keyboard, requiring a hard reboot every time.

## Root Cause Analysis

The ThinkPad P15v Gen 3 (AMD Rembrandt 680M iGPU + NVIDIA RTX A2000 Mobile dGPU) fails to suspend/resume due to a confluence of hardware and driver limitations:

1. **Firmware limitation**: The laptop BIOS only supports `s2idle` (S0ix modern standby), **not** S3 deep sleep. ACPI reports capabilities as `supports S0 S4 S5` — no S3. The `mem_sleep_default=deep` kernel parameter is silently ignored; the kernel falls back to s2idle.

2. **NVIDIA driver incompatibility**: The NVIDIA 580.x driver cannot properly suspend under s2idle. The driver's PM hooks hang, producing: `nvidia PM: failed to suspend async: error -5` (`-EIO`). The driver expects S3 semantics where the system fully powers down except RAM, not s2idle where CPU/GPU stay in low-power states.

3. **Module unload deadlock**: `nvidia_drm` cannot be unloaded before sleep because Hyprland/Aquamarine holds a reference to it. Killing the compositor defeats the purpose of sleep.

4. **PreserveVideoMemoryAllocations conflict**: With `NVreg_PreserveVideoMemoryAllocations=1`, the driver refuses to suspend without its procfs interface when the GPU is PCI-removed. With `=0`, a race condition causes the device to rebind before actual sleep begins.

5. **systemd 256+ bug**: `systemd-sleep` fails to freeze user sessions (nixpkgs #371058), causing timeouts during sleep transitions even if the driver cooperated.

## Investigation Steps (What Was Tried)

### Attempt 1: PRIME Offload Alone
Switch from NVIDIA-as-primary to PRIME offload (AMD renders, NVIDIA on-demand via `nvidia-offload`). Remove NVIDIA-forcing session variables.

**Result**: Improved graphics stability but did NOT fix suspend. NVIDIA driver still attempts to suspend even when not driving the display.

### Attempt 2: Force S3 Deep Sleep
Add `mem_sleep_default=deep` to kernel parameters.

**Result**: Failed silently. Firmware doesn't support S3. Kernel tried deep, immediately fell back:
```
PM: suspend entry (deep)
PM: suspend exit
PM: suspend entry (s2idle)
```

### Attempt 3: Module Unload Before Suspend
Systemd service to `modprobe -r nvidia_drm nvidia_modeset nvidia_uvm nvidia` before sleep.

**Result**: Deadlock. `nvidia_drm` is held by Hyprland compositor. Module unload hangs, blocking the entire sleep sequence.

### Attempt 4: PCI Device Unbind/Remove
Unbind NVIDIA from PCI driver (`driver/unbind`) and PCI-remove the device before suspend, rescan on resume.

**Result**: Service ordering bug — `nvidia-resume-rebind` fired before actual sleep (both triggered by `sleep.target`). The freshly-rebound GPU then failed to suspend: `PreserveVideoMemoryAllocations module parameter is set. System Power Management attempted without driver procfs suspend interface`.

### Attempt 5: Fixed Ordering + All Workarounds
Fixed service ordering to use `systemd-suspend.service` instead of `sleep.target`. Added `NVreg_PreserveVideoMemoryAllocations=0`, `NVreg_EnableGpuFirmware=0`, and `SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false`.

**Result**: Still unreliable. Various issues persisted with services being suspended but system not actually entering sleep.

### Why Each Approach Failed

| Approach | Why It Failed |
|----------|---------------|
| PRIME offload only | Driver tries to suspend regardless of display role |
| `mem_sleep_default=deep` | Firmware only implements S0/S4/S5; ignores S3 |
| Module unload | `nvidia_drm` held by compositor; unload hangs |
| PCI unbind/remove | Service ordering: device rebound before actual sleep |
| All workarounds combined | Race conditions; non-deterministic timing |

## Working Solution

Disable suspend entirely. Keep PRIME offload improvements for better GPU management and power efficiency.

### Changes Made

**`modules/nixos/nvidia.nix`** — Clean PRIME offload config:
```nix
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
      enableOffloadCmd = true;
    };
    amdgpuBusId = "PCI:102:0:0";
    nvidiaBusId = "PCI:1:0:0";
  };
};
```

**`modules/nixos/core.nix`** — SysRq safe subset for GPU hang recovery:
```nix
"kernel.sysrq" = 176;  # sync(16) + remount-ro(32) + reboot(128)
```

**`flake.nix`** — Remove semantically incorrect hardware module:
```diff
- nixos-hardware.nixosModules.common-gpu-nvidia-nonprime
```

**`modules/nixos/power.nix`** — Prevent TLP/finegrained PM conflicts:
```nix
RUNTIME_PM_DRIVER_DENYLIST = "nvidia";
```

**`home/linux/hyprlock.nix`** — Remove idle suspend trigger:
```diff
  listener = [
    { timeout = 300; on-timeout = "hyprlock"; }
-   { timeout = 900; on-timeout = "systemctl suspend"; }
  ];
```

**`home/linux/wlogout.nix`** — Remove suspend from power menu:
```diff
- {
-   "label" : "suspend",
-   "action" : "systemctl suspend",
-   "text" : "Suspend",
-   "keybind" : "s"
- }
```

## Prevention Strategies

### Re-enabling Suspend (When a Fix Becomes Available)

The infrastructure is in place for quick re-enablement:

1. Re-add the hypridle listener: `{ timeout = 900; on-timeout = "systemctl suspend"; }`
2. Re-add the wlogout suspend entry
3. Test with `systemctl suspend` and check `sudo journalctl -b | grep -i "suspend\|resume\|nvidia"`

### Checking for Driver Fixes

- Monitor NVIDIA release notes for s2idle/S0ix resume fixes
- Subscribe to [NVIDIA/open-gpu-kernel-modules releases](https://github.com/NVIDIA/open-gpu-kernel-modules/releases)
- After driver updates, check: `cat /sys/power/mem_sleep`

### BIOS/Firmware Updates

Lenovo ThinkPad BIOS updates sometimes add S3 support. After any BIOS update:
```bash
cat /sys/power/mem_sleep
# If "deep" appears in output, S3 is now available
```

### Hardware Purchase Guidance

Before purchasing laptops for Linux:
- Verify BIOS supports S3 deep sleep (check `cat /sys/power/mem_sleep` on demo units)
- AMD-only GPUs avoid these issues entirely
- Check [Arch Wiki hardware compatibility](https://wiki.archlinux.org/title/Laptop) for the model

### Alternative Power-Saving (Current Setup)

- Screen locks at 5 minutes via hypridle
- TLP manages CPU/GPU power on battery (`powersave` governor, `low-power` profile)
- PRIME offload keeps NVIDIA idle when not explicitly used
- Manual screen off: `hyprctl dispatch dpms off`

## Related Documentation

- [Brainstorm: Suspend/Resume Fix](../../brainstorms/2026-03-02-suspend-resume-fix-brainstorm.md)
- [Plan: Fix Suspend/Resume](../../plans/2026-03-02-fix-suspend-resume-hybrid-gpu-plan.md)
- [NixOS Wiki — NVIDIA](https://wiki.nixos.org/wiki/NVIDIA)
- [Arch Wiki — NVIDIA Troubleshooting](https://wiki.archlinux.org/title/NVIDIA/Troubleshooting)
- [nixpkgs #371058 — systemd sleep freeze](https://github.com/NixOS/nixpkgs/issues/371058)
- [NVIDIA/open-gpu-kernel-modules #922](https://github.com/NVIDIA/open-gpu-kernel-modules/issues/922)
- [PR #6 — fix/suspend-resume](https://github.com/jvall0228/nix-config/pull/6)
