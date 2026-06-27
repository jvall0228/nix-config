---
title: "CUA — Computer-Use-Agent Capability"
type: reference
status: active
date: 2026-06-26
---

# CUA — Computer-Use Agent for Hyprland

A harness-agnostic capability that lets any AI agent (claude, codex, gemini,
opencode) **see** and **act** on the Wayland desktop. Modeled on the
`agent-status` daemon: a user-level broker publishes a status JSON any tool can
read, and a single `cua` CLI is the entry point every agent shells out to — no
per-harness plugin or MCP server.

This is **Approach A: serialized single seat**. Hyprland has one seat (one
cursor, one keyboard); the daemon serializes all action through a lease. Nested
per-agent compositors (true parallel action) and the `cua see --tree`
accessibility fallback are declared-but-deferred — see "Deferred".

Requirements/decisions of record: `docs/brainstorms/2026-06-26-multi-agent-cua-requirements.md`.

## Architecture

```
   agents (claude/codex/gemini/opencode)
        │  shell out
        ▼
     cua CLI ──────────────► cua.sock (Unix stream, sync replies)
        │ poll                    │
        ▼                         ▼
  cua-status.json ◄──── cua daemon (home/linux/cua-daemon.py)
   (tmpfs, 1 Hz)         │  owns: seat lease, target registry
        │                │  drives: hyprctl (focus/outputs),
        ▼                │          grim (see), ydotoold (act)
  waybar custom/cua      ▼
  (DRIVING pill)     ydotoold (user service) ── /dev/uinput
```

- **Producer:** `home/linux/cua.nix` runs `cua-daemon.py` as a `Type=simple`
  systemd **user** service bound to `graphical-session.target`, plus a
  user-level `ydotoold`. The daemon self-discovers `HYPRLAND_INSTANCE_SIGNATURE`
  / `WAYLAND_DISPLAY` from `$XDG_RUNTIME_DIR` so it works regardless of env
  import.
- **Read-only consumers poll** `cua-status.json` (waybar, `cua status`); **action
  verbs use the socket** because they need synchronous replies (lease grant/deny,
  capture path, focus-restore completion).

## Targets

A **target** is what an agent sees/acts on. Every call names one (default `real`):

| Target | Meaning |
|--------|---------|
| `real` | The user's physical desktop (focused output). Push-to-grant only. |
| `sandbox-N` | A spawned off-screen Hyprland headless output (`cua target new --headless`). Self-serve. |

`sandbox=true` is the predicate that authorizes self-serve `acquire`; `real`
never self-serves. Headless outputs are capped (default 2) to bound GPU/memory
cost on the Radeon 680M. (Workspace-style sandbox targets are **not** supported:
a workspace shares the real output, so `grim -o` would capture the user's actual
screen — a privacy leak — and focusing it would switch the visible view.
Headless outputs are the only correct isolation primitive.)

## The seat lease (serialization + control model)

There is one seat. The daemon grants it as a lease; only the holder may inject.

```
                 acquire(sandbox)  [self-serve, R16]
   ┌──────────────────────────────► ACQUIRED ──┐
   │                                            │ release / 5m timeout / panic
 FREE ◄────────────────────────────────────────┘
   │  USER: cua grant <agent> real [--lock]
   │        (mints a push-to-grant token; agents may NOT grant real)
   ▼  agent: cua acquire real  (consumes token)
 GRANTED ──────────────────────────────────────► FREE
          release / revoke / panic / timeout
```

- **`acquire real` with no standing grant → denied (`NEEDS_GRANT`).** The seat
  does not move; nothing is injected (R12, AE1).
- **Sandbox `acquire` is self-serve**; if the seat is busy the request is queued
  FIFO and promoted on release (R10).
- **Lease auto-expires after 5 minutes idle** (refreshed by each action).

### Safety (real desktop)

- **Push-to-grant (cooperative).** The daemon rejects a `grant`/`revoke real`
  from a peer it identifies as an agent (socket `SO_PEERCRED` + `/proc` walk),
  and an agent calling `acquire real` without a standing grant gets
  `NEEDS_GRANT`. This stops *well-behaved* agents from grabbing your seat by
  accident. It is **not a security boundary** — see "Trust boundary" below.
- **Panic — hard guarantee (R14).** `Super+Shift+Escape` (a `bindl`, fires even
  while locked) or `cua panic` runs `cua-panic.sh`: `systemctl --user stop
  ydotoold.service` (stop, not kill — `Restart=always` would otherwise revive a
  *killed* injector within ~1s, possibly before the lease clears). Stopping
  ydotoold destroys the uinput device — the kernel synthesizes key/button
  releases (no stuck modifiers) and in-flight injection dies. A synchronous
  revoke-flag guard also refuses any further injection immediately; the daemon
  then clears the lease and restarts ydotoold for next time. Typing goes through
  `ydotool` (not `wtype`) precisely so this one kill covers it.
- **Lockout (`--lock`, R15) — best-effort, pointer only.** When granted with
  `--lock`, the daemon disables the **pointer** devices
  (`hyprctl keyword device[..]:enabled false`) so the user's mouse can't fight
  the agent. **The keyboard is deliberately left enabled** so the panic key can
  never be deadlocked. Full keyboard parking is deferred to the optional
  EVIOCGRAB+chord helper. `cua-panic.sh` re-enables the disabled devices
  *independently* (not relying on the daemon being healthy), and the daemon
  clears any stale lockout on startup. So today, `--lock` parks the pointer; it
  does not fully isolate the keyboard.

### Trust boundary (read this)

Push-to-grant is a **cooperative control within one Unix user, not a security
boundary.** All four agents run as the same user (`javels`); they share the
ydotool socket and `input`-group access to `/dev/uinput`. That means a
*determined* same-UID process can bypass the broker entirely:

- It can call `ydotool` (or open `/dev/uinput`) directly, injecting input with
  no `cua grant` at all.
- It can read the grant-token file the daemon writes (mode 0600, same UID) and
  present it, or detach a helper so the daemon's `/proc` walk no longer
  classifies it as an agent.

What the broker *does* guarantee: a **well-behaved** agent that uses `cua` cannot
take the real seat unannounced, the authority check is **fail-closed** (a
`/proc`-read failure or pid-reuse can't be mistaken for the user — it now
requires the grant token, not merely "unidentifiable"), and **panic always works
on the broker's own injector**. That is the right model for *trusted* agents (your
own AI tools) where the goal is preventing accidental cursor hijacking.

**Real boundary (not built):** to enforce grant against an adversarial same-UID
agent, the injector must live under a *different principal* — run `ydotoold`
(and a thin injection helper) as a dedicated system user/group with the socket
private to it, so agents-as-`javels` can reach uinput *only* through the broker.
That also removes the `input`-group-for-the-user keylogging tradeoff below. It is
a meaningful re-architecture, deferred until the threat model needs it.

## CLI

```sh
# PERCEPTION (no lease)
cua see [TARGET] [--region X,Y WxH] [--out FILE] [--tree]

# SEAT / CONTROL
cua acquire <TARGET>                  # sandbox: self-serve; real: needs grant
cua release
cua grant <AGENT> [TARGET] [--lock]   # USER mints push-to-grant for real
cua revoke [AGENT]                    # USER revokes grant / active lease
cua panic                             # hard-stop, seat back to user

# ACTION (must hold the lease)
cua click  [TARGET] [--button left|right|middle] [--x N --y N]
cua type   [TARGET] -- <text>
cua scroll [TARGET] [--dir up|down] [--amount N]
cua key    [TARGET] -- <keycode:state ...>      # e.g. 29:1 46:1 46:0 29:0 = Ctrl+C

# TARGETS
cua target list
cua target new [--headless] [--spawn CMD]
cua target rm <ID>
cua target select <ID>                # set this shell's default target

# STATUS
cua status [--json|-j] [--watch|-w]
```

`cua see` returns a PNG path. Clicks take **target-local** coordinates; the
daemon adds the target output's global offset before injecting.

## JSON schema (`$XDG_RUNTIME_DIR/cua-status.json`)

```jsonc
{
  "updated": "2026-06-26T14:03:11",
  "updatedNs": "1750000000000000000",   // heartbeat / staleness
  "host": "thinkpad",
  "driving": true,                        // agent holds the REAL seat (waybar alarm)
  "lease": {                              // null when free
    "holder": "claude", "target": "real", "kind": "granted",
    "locked": true, "since": "...", "expiresAt": "..."
  },
  "queue": ["codex"],                     // FIFO waiters
  "targets": [ { "id": "real", "kind": "real", "output": "eDP-1", "sandbox": false }, ... ],
  "grants": { "claude": "real" }          // standing push-to-grant tokens
}
```

`driving` is true only while an agent holds the **real** seat (sandbox leases
don't trip the alarm). Tolerate a missing/stale file as "idle", like every
agent-status consumer.

## Requirements coverage

| R | Where |
|---|-------|
| R1 single `cua` CLI, no MCP | `home/linux/cua.nix` |
| R2 user daemon + runtime JSON | `cua-daemon.py`, mirrors agent-status |
| R3 full verb set | CLI dispatcher |
| R4–R6 targets (real / headless sandbox) | daemon `Daemon.resolve`/`all_targets` |
| R7 `see` via grim | `v_see` (`grim -o <output>`) |
| R8 perception needs no lease | `v_see` (no holder check) |
| R9 inject via ydotool | `v_click`/`v_type`/`v_scroll`/`v_key` |
| R10 serialized seat + queue | lease state machine |
| R11 focus save/restore | `save_focus`/`focus_target`/`restore_focus` |
| R12 push-to-grant for real | `v_acquire` `NEEDS_GRANT`; `v_grant` rejects agents |
| R13 DRIVING indicator | `home/linux/waybar.nix` `custom/cua` |
| R14 panic | `cua-panic.sh` + `Super+Shift+Escape` bindl |
| R15 lockout (pointer, best-effort) | `lock_input`/`unlock_input` |
| R16 self-serve only for sandboxes | `v_acquire` `sandbox` branch |

## Operating

```sh
systemctl --user status  cua ydotoold     # health
systemctl --user restart cua              # after editing the daemon + rebuild
journalctl --user -u cua -f                # logs
cua status --watch                         # live state
```

### Activation (first time)

```sh
bash apps/build-switch thinkpad     # applies modules/nixos/cua.nix + home modules
# LOG OUT AND BACK IN ONCE — the `input` group + uinput udev rule need a fresh login
systemctl --user status ydotoold cua       # both active after relogin
```

## Security tradeoff

`modules/nixos/cua.nix` puts the user in the **`input` group** and adds a udev
rule giving the group `/dev/uinput`. `input`-group membership confers read
access to all `/dev/input/event*` — i.e. **system-wide keylogging capability**.
This is an intentional loosening of this host's otherwise-hardened posture
(`modules/nixos/core.nix`), accepted because thinkpad is a single-user,
LUKS-encrypted workstation. **Do not enable on a multi-user host.** The
alternative (`programs.ydotool.enable`, a root system service) avoids the group
but breaks the user-session lifecycle and the `systemctl --user kill` panic
primitive.

## Deferred (declared behind the same CLI)

- **Nested per-agent compositors (Approach B)** — each agent its own seat for
  genuine parallel action. Build when serialized-seat contention is real.
- **`cua see --tree`** — text/accessibility perception for harnesses that can't
  read screenshots. The verb exists and returns `DEFERRED`.
- **EVIOCGRAB + panic-chord helper** — full keyboard lockout that still honors
  panic; would make R15 isolate the keyboard, not just the pointer.
- **Mascot / lock-screen DRIVING flip** — `hyprlock.nix` border-color or a
  `cua-driving` sprite. Left out of v1 to avoid destabilizing the JRPG widget;
  the waybar pill covers R13.

## Files

| file | role |
|------|------|
| `home/linux/cua-daemon.py` | seat broker + target registry + status publisher |
| `home/linux/cua.nix` | `cua` CLI, `cua-panic` bin, `ydotoold` + `cua` user services |
| `home/linux/cua-panic.sh` | panic body (kill ydotoold; daemon clears the rest) |
| `modules/nixos/cua.nix` | uinput kernel module + udev rule + `input` group |
| `home/linux/waybar.nix` | `custom/cua` DRIVING indicator |
| `home/linux/hyprland.nix` | panic `bindl` + session-env import |
| `modules/nixos/agent-context.nix` | advertises `cua` in `/etc/agent-context.md` |

## Known risks / version-sensitivity

- **Hyprland 0.52.2 classic dispatchers** are assumed (NixOS 25.11). On 0.55+
  the `hyprctl dispatch`/`keyword device[..]:enabled` forms change — branch on
  `hyprctl version` if the box moves to unstable.
- **`device[..]:enabled false`** can't be queried back (hence the
  `cua.locked-devices` state file) and is version-fragile.
- **Absolute click coordinates** can be skewed by pointer acceleration; if
  clicks land off, set `input.accel_profile = "flat"` in `home/linux/hyprland.nix`
  (left unset by default so the daily-driver pointer feel is untouched).
- **HEADLESS output names** are not guessable — the daemon reads them back from
  `hyprctl monitors all -j` after `output create`.
