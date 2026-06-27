---
date: 2026-06-26
topic: multi-agent-cua
origin: docs/brainstorms/2026-06-26-multi-agent-cua-requirements.md
status: implemented (pending user rebuild + relogin)
---

# Multi-Agent CUA — Implementation Plan

Approach A (serialized single seat) from the requirements. Clones the
`agent-status` daemon/CLI/waybar stack. Reference: `docs/cua.md`.

## Summary

A harness-agnostic `cua` CLI + user daemon lets any agent see (grim) and act
(ydotool) on Hyprland targets — the user's real desktop behind push-to-grant +
panic safety, or self-serve off-screen sandbox outputs. One privileged change
(uinput access); everything else is user-session scoped. Nested compositors and
`see --tree` are deferred behind the same CLI.

## Key decisions (resolved during build)

- **User-level `ydotoold`**, not `programs.ydotool.enable` — matches the
  agent-status user lifecycle and makes panic a clean `systemctl --user kill`.
  Cost: needs the `input` group for `/dev/uinput`.
- **Daemon self-discovers Hyprland/Wayland env** from `$XDG_RUNTIME_DIR` (plus a
  belt-and-suspenders `systemctl --user import-environment`), so it doesn't
  depend on systemd env import ordering.
- **Lockout parks the pointer only**, keyboard stays live — so the physical
  panic key can never be deadlocked. Full keyboard lockout is deferred to an
  EVIOCGRAB+chord helper.
- **Pointer feel untouched** — `accel_profile` left at the user's `sensitivity =
  0.5`; documented as an opt-in calibration knob.
- **hyprlock not modified** — R13 lands via the waybar pill; mascot/lock-screen
  flip deferred to avoid destabilizing the JRPG widget.

## Implementation units

- U1. uinput access — `modules/nixos/cua.nix`: `boot.kernelModules=["uinput"]`,
  udev rule (`GROUP="input" MODE="0660"`), `users.users.${user}.extraGroups +=
  ["input"]` (merges with core.nix). Attached at `flake.nix` thinkpad modules.
- U2. ydotoold user service — `home/linux/cua.nix`: socket `%t/.ydotool_socket`,
  `Restart=always`.
- U3. cua daemon — `home/linux/cua-daemon.py`: Unix-socket broker, lease state
  machine, target registry, `grim`/`ydotool`/`wtype` action, focus save/restore,
  atomic `cua-status.json` publish, fail-soft loop. PATH injected by the unit.
- U4. cua CLI — `home/linux/cua.nix` (`writeShellApplication`): all verbs;
  read-only verbs poll JSON, stateful verbs hit the socket via `socat`.
- U5. Panic — `home/linux/cua-panic.sh` + `home/linux/hyprland.nix` bindl
  `Super+Shift+Escape`.
- U6. DRIVING indicator — `home/linux/waybar.nix` `custom/cua` (red pill, 1s
  poll, auto-hide).
- U7. Discovery — `modules/nixos/agent-context.nix`: `cua` section so all four
  agents find the capability in `/etc/agent-context.md`.
- U8. Docs — `docs/cua.md` (schema, verbs, safety, R-map, risks).

## Validation done (static)

- `python3 -m py_compile` on the daemon; `bash -n` on the panic script — pass.
- `nix-instantiate --parse` on all six new/edited `.nix` — pass.
- `nixos-rebuild dry-build --flake .#thinkpad` — evaluates clean (after staging
  the new files; flakes only see git-tracked paths).
- Realized `cua` / `cua-panic` / `waybar-cua` derivations — `writeShellApplication`
  shellcheck + `bash -n` pass.
- Ran the built `cua --help` / `status` / arg-validation; imported the daemon
  module and exercised helpers — pass.

## Activation + runtime smoke test (user)

```sh
bash apps/build-switch thinkpad
# LOG OUT AND BACK IN ONCE (input group + uinput udev rule)
systemctl --user status ydotoold cua          # both active
```

Then per requirement:

| Req | Test |
|-----|------|
| R1–R3 | `cua status`; `cua --help`; `cua-status.json` mtime ticks ~1s. |
| R4–R6 | `cua target list` shows `real`; `cua target new --headless` → `sandbox-N`, new `HEADLESS-*` in `hyprctl monitors all -j`, your view doesn't switch. |
| R7/R8 | `cua see real -o /tmp/r.png` → valid PNG; two concurrent `cua see real` while typing — both land, typing uninterrupted, no lease. |
| R9–R11 | hold a sandbox lease; `cua click sandbox-1 --x 100 --y 100`, `cua type sandbox-1 -- hello`; focus returns, view never switched. |
| R12/AE1 | `cua acquire real` with no grant → `NEEDS_GRANT`, seat unmoved. Then `cua grant claude real`; `cua acquire real` succeeds. |
| R13 | while driving real, red `custom/cua` pill shows; `.driving==true`. |
| R14/AE3 | mid-action, press `Super+Shift+Escape` → injection dies, lease clears within a tick, pill disappears. |
| R15 | `cua grant claude real --lock` → pointer parked, keyboard (incl. panic) live; release/panic restores pointer. |
| R16 | `cua acquire sandbox-1` self-serves; `cua acquire real` never does. |

## Deferred

Nested compositors (B); `cua see --tree`; EVIOCGRAB keyboard lockout; mascot/
lock-screen DRIVING flip; `accel_profile=flat` calibration. See `docs/cua.md`.
