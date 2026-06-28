---
date: 2026-06-28
topic: Unified lock curtain — agent-mode renders the identical hyprlock scene
status: requirements (ready for ce-plan)
refines: docs/brainstorms/2026-06-26-multi-agent-cua-requirements.md (R17 agent-mode lock)
---

# Unified Lock Curtain

## Summary

The agent-mode lock (R17) currently shows a kitty TUI curtain (`home/linux/cua-curtain.sh`) that looks nothing like the user's real hyprlock. Make the agent-mode curtain **pixel-perfect identical** to hyprlock by **reusing hyprlock itself** rather than reimplementing its scene. Chosen mechanism: **patch hyprlock to add a non-locking "overlay" mode** that renders the same config-driven scene onto a layer-shell surface (no `ext-session-lock`, no auth), bound to the physical output, so the agents' off-screen stage stays capturable. One binary, one config, zero scene duplication; the kitty curtain retires.

## Problem Frame

- hyprlock is the lock scene's single source of truth — background (blurred `assets/wallpaper.png`), animated avatar, `mainbox`/`userbox` PNGs, and the clock/date/weather + JRPG header/dialogue/user labels — defined in `home/linux/hyprlock.nix` and driven by the shared `clawd-*` cache pipeline.
- hyprlock is an `ext-session-lock-v1` client; that protocol blanks **all** outputs from screencopy. That is exactly why agent-mode cannot use hyprlock directly — it would blank the off-screen "stage" the agents capture.
- The current curtain is a separate kitty TUI: functional but obviously not hyprlock. Any AGS/other replica would be a **second renderer of the same scene** that drifts over time — the "two services doing the same thing" the user wants to avoid.
- Goal: the agent-mode curtain must look identical to hyprlock **and** the scene must be maintained in exactly one place.

## Key Decisions

- **KD1 — Fidelity = pixel-perfect** (byte-identical), per the user. Reachable only via hyprlock's own renderer.
- **KD2 — Mechanism = a non-locking "overlay" mode of hyprlock** (a maintained patch/fork), NOT a reimplementation. Reuses hyprlock's renderer + config → identical by construction + zero scene duplication.
  - Rejected: a shared-scene **AGS replica** (it is the duplication being avoided — two renderers); **nested real hyprlock** piped to the curtain (pixel-perfect but a whole second compositor + 4K capture loop — kept only as the fallback under OQ-feasibility).
- **KD3 — Overlay mode is display-only**: no PAM/auth. The hyprlock scene here has no visible password field; agent-mode unlock stays `Super+Shift+U` / panic via the `agentlock` submap.
- **KD4 — Overlay binds to the physical output only**, leaving the headless stage uncovered and capturable.

## Requirements

- **R1.** Agent-mode's on-screen curtain renders the identical hyprlock scene (wallpaper+blur, avatar, mainbox/userbox, clock/date/weather, JRPG header/dialogue/user), pixel-for-pixel, from the same config + `clawd-*` caches.
- **R2.** The lock scene's layout/assets are defined in exactly **one place** (the hyprlock config); no second copy of the layout exists.
- **R3.** The overlay renderer does **not** acquire `ext-session-lock`; the agents' off-screen stage remains screencopy-able while the curtain is up.
- **R4.** The overlay is **display-only** (no password entry/auth). Human input stays governed by the existing `agentlock` submap + pointer-park; panic/unlock unchanged.
- **R5.** The overlay covers only the physical output(s); it must **not** render on the headless stage.
- **R6.** The cua daemon spawns/closes the overlay in place of the kitty curtain across all agent-mode paths (enter / exit / teardown / crash-recovery); `cua-curtain.sh` is retired.
- **R7.** Normal hyprlock (real `ext-session-lock`) behavior is unchanged.
- **R8.** Live content (agent dialogue/avatar cycling) works in the overlay via the existing `clawd-*` pipeline, identical to hyprlock.

## Scope Boundaries

- **In:** a hyprlock patch (overlay/no-lock + display-only + output-bind); daemon wiring to spawn/close it; retiring `cua-curtain.sh`.
- **Out:** the AGS replica; a from-scratch scene reimplementation; any change to the lock scene's design.
- **Fallback** (only if R3 via overlay proves infeasible in hyprlock's C++): nested real hyprlock piped to the curtain — still pixel-perfect, still reuses hyprlock, heavier.

## Success Criteria

- **AE1.** With agent-mode active, a `grim` of the physical output is visually indistinguishable from a real hyprlock screen (same scene, live clock/dialogue).
- **AE2.** With agent-mode active, `cua see real` still captures the live desktop on the stage (the overlay did not blank it).
- **AE3.** Editing the lock scene's layout/assets in one file changes both the real lock and the agent-mode curtain.
- **AE4.** Panic / `Super+Shift+U` still exit agent-mode; the overlay never authenticates a password.

## Outstanding Questions / Risks (for ce-plan)

- **OQ1 — FEASIBILITY (load-bearing).** Does hyprlock's C++ separate lock-acquisition from scene-rendering enough to add a layer-shell render path without `ext-session-lock`? ce-plan must read hyprlock's source and confirm **before** committing; if infeasible, take the nested-hyprlock fallback.
- **OQ2 — Packaging.** Prefer the smallest patch via `pkgs.hyprlock.overrideAttrs { patches = [ … ]; }` (tracks upstream) over a hard fork.
- **OQ3 — Multi-output.** Agent-mode currently targets the single focused physical output; the overlay should match that scope.
- **OQ4 — Upstream.** Consider proposing a render-only/overlay mode upstream to avoid long-term patch maintenance.
