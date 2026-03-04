# Brainstorm: Fix Suspend/Resume Freeze on Hybrid GPU Laptop

**Date:** 2026-03-02
**Status:** Ready for planning

## What We're Building

Fix the system freeze that occurs every time the laptop resumes from idle suspend. Currently, after hypridle triggers `systemctl suspend` (15-minute idle timeout), waking the laptop produces a black screen with a blinking cursor and a completely unresponsive keyboard, requiring a hard reboot.

## Why This Approach

**Root cause:** The NVIDIA discrete GPU (RTX A2000 Mobile) is configured as the primary renderer on a hybrid AMD+NVIDIA laptop without proper PRIME offload or VRAM preservation. When the system suspends, NVIDIA loses video memory allocations and fails to restore the display pipeline on resume, hanging the GPU and freezing the system.

**Chosen approach:** Configure proper PRIME offload (AMD iGPU as primary display, NVIDIA dGPU available on-demand) with full NVIDIA suspend/resume infrastructure.

**Why not alternatives:**
- *Minimal fix only:* Keeping NVIDIA as primary renderer on a hybrid laptop is unusual and wastes power. PRIME offload is the correct architecture.
- *Disable NVIDIA entirely:* User plans to use CUDA/ML and gaming workloads in the future.

## Key Decisions

1. **PRIME offload mode** — AMD Radeon 680M (bus `PCI:102:0:0`) handles all display output. NVIDIA RTX A2000 Mobile (bus `PCI:1:0:0`) activates only when explicitly requested via `nvidia-offload` wrapper or for CUDA workloads.

2. **NVIDIA suspend infrastructure** — Add `NVreg_PreserveVideoMemoryAllocations=1` kernel parameter and enable `powerManagement.finegrained = true` for proper dGPU power cycling during suspend/resume.

3. **Remove NVIDIA-as-primary session variables** — Remove `GBM_BACKEND=nvidia-drm`, `__GLX_VENDOR_LIBRARY_NAME=nvidia`, and `LIBVA_DRIVER_NAME=nvidia` from session environment. These force NVIDIA as the primary renderer, conflicting with PRIME offload.

4. **Enable SysRq for recovery** — Change `kernel.sysrq` from `0` to `1` (or a restricted bitmask) so the system can be recovered from GPU hangs without hard reboots during debugging.

5. **nvidia-offload wrapper** — Provide a convenience script/alias so the user can easily run GPU-heavy apps on the dGPU (e.g., `nvidia-offload steam`).

## Changes Required

### `modules/nixos/nvidia.nix`
- Add `hardware.nvidia.prime.offload.enable = true`
- Add `hardware.nvidia.prime.offload.enableOffloadCmd = true` (provides `nvidia-offload`)
- Add `hardware.nvidia.prime.amdgpuBusId = "PCI:102:0:0"`
- Add `hardware.nvidia.prime.nvidiaBusId = "PCI:1:0:0"`
- Add `hardware.nvidia.powerManagement.finegrained = true`
- Remove or adjust `environment.sessionVariables` that force NVIDIA as primary

### `modules/nixos/core.nix`
- Add `nvidia.NVreg_PreserveVideoMemoryAllocations=1` to `boot.kernelParams`
- Change `kernel.sysrq = 0` to `kernel.sysrq = 1` (or `176` for safe subset)

### `home/linux/hyprlock.nix` (verify)
- Confirm `after_sleep_cmd` still works correctly with the new GPU setup

## Open Questions

*None — all questions resolved during brainstorm.*

## Hardware Reference

- **iGPU:** AMD Rembrandt Radeon 680M — `66:00.0` → `PCI:102:0:0`
- **dGPU:** NVIDIA RTX A2000 Mobile (GA107GLM) — `01:00.0` → `PCI:1:0:0`
- **Swap:** 16GB swapfile on Btrfs @swap subvolume (hibernation-ready)
