---
title: "fix: Unblock and fix suspend on ThinkPad P15v (NVIDIA hybrid GPU)"
type: fix
status: todo
date: 2026-03-06
---

# fix: Unblock and Fix Suspend

## Problem

Suspend is configured for lid-close (`HandleLidSwitch = "suspend"` in `power.nix`) but there is no manual trigger and suspend/resume likely fails or causes issues on this NVIDIA hybrid GPU (AMD iGPU + NVIDIA dGPU) laptop.

## Known Issues

1. **No manual suspend option** — wlogout layout has lock, logout, reboot, shutdown but no suspend entry
2. **No Hyprland keybind** — no `bind` for `systemctl suspend` in hyprland config
3. **NVIDIA suspend/resume** — hybrid GPU laptops commonly fail to resume from suspend; screen stays black, GPU hangs, or Wayland compositor crashes
4. **`nvidia-resume.service` / `nvidia-hibernate.service`** — may need to be enabled or configured for proper VRAM save/restore

## Investigation Steps

- [ ] Test `systemctl suspend` manually and check if resume works
- [ ] Check `journalctl -b -1 -p err` after a failed resume for NVIDIA errors
- [ ] Verify `nvidia-suspend.service`, `nvidia-resume.service`, and `nvidia-hibernate.service` are active
- [ ] Check if `hardware.nvidia.powerManagement.enable = true` (already set) is sufficient or if additional kernel params are needed (`mem_sleep_default=deep`, `nvidia.NVreg_PreserveVideoMemoryAllocations=1`)
- [ ] Test with `finegrained = false` to rule out runtime PM conflicts

## Fix Checklist

- [ ] Add suspend entry to wlogout layout (`systemctl suspend`, keybind `s`)
- [ ] Add Hyprland keybind for suspend (e.g., `$mainMod SHIFT, S`)
- [ ] Add `nvidia.NVreg_PreserveVideoMemoryAllocations=1` to `boot.kernelParams` if needed
- [ ] Add `boot.kernelParams = [ "mem_sleep_default=deep" ]` if S3 sleep is preferred over s2idle
- [ ] Ensure `services.nvidia-suspend.enable = true` and related resume/hibernate services
- [ ] Test full cycle: suspend via keybind → resume → verify display, GPU, Wayland session intact
- [ ] Verify lid-close suspend still works after changes

## Relevant Files

- `modules/nixos/power.nix` — logind suspend config
- `modules/nixos/nvidia.nix` — NVIDIA driver and power management
- `home/linux/wlogout.nix` — power menu layout (missing suspend)
- `home/linux/hyprland.nix` — keybinds
- `home/linux/hyprlock.nix` — hypridle `before_sleep_cmd` / `after_sleep_cmd`
