---
status: pending
priority: p3
issue_id: "008"
tags: [cua, agent-mode, ags, lock-screen, hyprlock, ui]
dependencies: []
---

# Finish the AGS Agent-Mode Lock Curtain (separate-services approach)

## Problem Statement

Make the cua agent-mode curtain look like hyprlock via a NON-locking AGS overlay
(the lighter "separate services" path; the pixel-perfect hyprlock fork is `todos/007`).
Reuses the same assets + `clawd-*` cache pipeline so the scene content stays shared;
the LAYOUT is the only duplicated part (accepted tradeoff). AGS is software-rendered
here, so the layer-shell surface paints fine on the hybrid GPU (sidesteps the EGL risk).

## State so far (committed `6812cef`, NOT visually verified)

- `home/linux/ags/widgets/AgentLock.tsx` — fullscreen overlay window, `createState`
  visible, exports `showAgentLock`/`hideAgentLock`. **Spike only:** blurred wallpaper bg
  + clock. Toggled via `ags request agentlock show|hide` (handler in `app.ts`).
- `home/linux/ags.nix` — `wallpaperBlur` runCommand (imagemagick `-blur 0x20 -modulate 70`,
  tune to match hyprlock's `blur_size 6 / passes 3 / brightness 0.7`) injected into configDir
  as `agentlock-wallpaper-blur.png`; CSS in `style.css` `.agentlock-*`.
- `home/linux/ags/lib/utils.ts` — `shSync` made fail-soft (was crashing all of AGS when
  hypridle stopped: `Dashboard.tsx:25` `systemctl is-active` exits 3 → exec threw).

## Remaining work

1. **Replicate the full JRPG scene** (match `home/linux/hyprlock.nix` `programs.hyprlock.settings`):
   - avatar PNG (poll `clawd-avatar-frame`; idle = `assets/avatar.png`), pos `0,-720` top-center, size 300, blue border.
   - `mainbox.png` (pos `0,-150`) + `userbox.png` (pos `0,-20`) — show when `clawd-pgrep-check` succeeds, else hidden. Reuse the SAME `boxAssets` runCommand (factor it out of hyprlock.nix into a shared module so both consume it).
   - labels (JetBrainsMono Nerd Font): time 64px `0,-40` base08; date 20px `0,-120` base05; weather 16px `0,-155`; JRPG header 18px `0,-90` base0E (poll `clawd-jrpg-header`); dialogue lines 1-3 16px `0,-145/-173/-201` (cat `clawd-line-{1,2,3}`, Pango markup); user 18px `0,-20` (`clawd-jrpg-user`).
   - Use a Gtk.Fixed/Overlay for hyprlock's absolute anchor+offset positioning. Full spec was in the grounding dossier; the authoritative source is `home/linux/hyprlock.nix` lines ~411-579.
2. **Bind to the physical output only** (not the headless stage) — set `gdkmonitor` to eDP-1 so it doesn't render on the stage during agent-mode.
3. **Wire the cua daemon** (`home/linux/cua-daemon.py`): `_agentmode_enter` → `ags request agentlock show` instead of spawning kitty (CURTAIN_CLASS); `_agentmode_teardown` → `ags request agentlock hide`. **Retire `home/linux/cua-curtain.sh`** + its `cua-curtain` package in `cua.nix`.
4. **Visually verify** against a real hyprlock (grim both, compare).

## Testing gotcha (READ — cost a long detour)

See `[[hyprlock-test-unlock-pitfall]]`. Before any test needing an unlocked screen:
`systemctl --user stop hypridle` FIRST, and DON'T `build-switch` mid-test (it restarts
hypridle → auto-locks via `cua-idle-lock`). A re-attached hyprlock (lockdead +
`allow_session_lock_restore`) does NOT accept injected input — unrecoverable via ydotool.
