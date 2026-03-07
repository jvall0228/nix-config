---
title: "refactor: Address PR #14 code review findings for JRPG hyprlock widget"
type: refactor
status: completed
date: 2026-03-07
---

# refactor: Address PR #14 code review findings for JRPG hyprlock widget

## Overview

PR #14 (`feat/clawd-jrpg-user-label`) adds a JRPG-style dialogue widget to hyprlock showing Claude's last response with typewriter effects. A multi-agent code review identified 10 findings across security, architecture, readability, and pattern consistency. This plan addresses all findings in priority order.

The bug fix for HTML tags in user messages has already been applied (XML tag stripping in the Python parser). This plan covers the remaining structural improvements.

## Problem Statement

The JRPG widget works functionally but has:
1. **Security gap**: Conversation data written to world-readable `/tmp` files
2. **Architectural debt**: Weather service coupled to hyprlock, hardcoded colors bypassing Stylix
3. **Readability crisis**: 200-line render loop with 30 single-letter variables
4. **Minor hygiene issues**: Missing HTTPS, unnecessary fallbacks, no input validation

## Proposed Solution

Implement all 10 findings in 4 phases, ordered by dependency and impact.

## Implementation Phases

### Phase 1: `/tmp` to `$XDG_RUNTIME_DIR` (P1 — Security)

**Findings addressed:** #1 (world-readable files), #4 (no cleanup), #9 (LINE validation)

Replace all `/tmp/clawd-*` and `/tmp/hyprlock-weather` paths with `$XDG_RUNTIME_DIR/clawd-*` and `$XDG_RUNTIME_DIR/hyprlock-weather`.

**Files:** `home/linux/hyprlock.nix`

**Changes:**
- [x] Define a shared `CACHE_DIR` variable at the top of each script: `CACHE_DIR="$XDG_RUNTIME_DIR"`
- [x] Replace all `/tmp/clawd-running` → `$CACHE_DIR/clawd-running`
- [x] Replace all `/tmp/clawd-jrpg-text` → `$CACHE_DIR/clawd-jrpg-text`
- [x] Replace all `/tmp/clawd-jrpg-user` → `$CACHE_DIR/clawd-jrpg-user`
- [x] Replace all `/tmp/clawd-jrpg-ts` → `$CACHE_DIR/clawd-jrpg-ts`
- [x] Replace all `/tmp/clawd-line-{1,2,3}` → `$CACHE_DIR/clawd-line-{1,2,3}`
- [x] Replace `/tmp/hyprlock-weather` → `$CACHE_DIR/hyprlock-weather` (in both the systemd service and the hyprlock label)
- [x] Update the Python parser's hardcoded `/tmp/clawd-jrpg-user` paths to use `os.environ.get("XDG_RUNTIME_DIR", "/tmp")` + `/clawd-jrpg-user`
- [x] Add LINE argument validation in `clawd-jrpg-text`: `[[ "$LINE" =~ ^[123]$ ]] || exit 1`

**Why `$XDG_RUNTIME_DIR`:**
- Per-user directory (`/run/user/<uid>`), mode `0700` — not world-readable
- tmpfs-backed, auto-cleaned on logout
- Always set on NixOS with systemd
- Fixes findings #1, #4, and partially #3 (symlink races) in one change

**Verification:**
- `ls -la /run/user/$(id -u)/clawd-*` shows files with `0600`/`0644` perms under user-private dir
- Lock screen still displays correctly after rebuild
- Files cleaned up after logout

### Phase 2: Variable Renaming in `clawd-jrpg-text` (P2 — Readability)

**Finding addressed:** #3 (single-letter variables)

Rename all 30 cryptic variables in the render loop (lines ~192-286) to descriptive names. Zero performance impact — bash variable name length has no cost.

**Files:** `home/linux/hyprlock.nix`

**Rename map:**

| Current | New Name |
|---------|----------|
| `AL` | `ALL_LINES` |
| `TL` | `TOTAL_LINES` |
| `TP` | `TOTAL_PAGES` |
| `TC` | `TIME_CONSUMED` |
| `PG` | `PAGE` |
| `PS_MS` | `PAGE_START_MS` |
| `PLS` | `PAGE_LINE_START` |
| `HM` | `HAS_MORE` |
| `PTC` | `PAGE_TOTAL_CHARS` |
| `PLC` | `PAGE_LINE_COUNT` |
| `PE` | `PAGE_ELAPSED` |
| `TY` | `TYPED_CHARS` |
| `BL` | `BLINK` |
| `CO` | `CHAR_OFFSET` |
| `LI` | `LINE_INDEX` |
| `LN` | `LINE_NUM` |
| `FL` | `FULL_LINE` |
| `LL` | `LINE_LEN` |
| `V` | `VISIBLE` |
| `SC` | `STILL_TYPING` |
| `ILP` | `IS_LAST_PAGE_LINE` |
| `EL` | `ELLIPSIS` |
| `E` | `ESCAPED` |
| `C` | `CURSOR_STR` |
| `VL` | `VISIBLE_LEN` |
| `ELL` | `ELLIPSIS_LEN` |
| `CL` | `CURSOR_LEN` |
| `PL` | `PAD_LEN` |
| `P` | `PADDING` |
| `O` | `OUTPUT` |
| `M` | `MARGIN` |

**Also rename in the page-finding loop:**
- `p` → `pg` (loop var)
- `j` → `line_idx` (inner loop var)
- `PC` → `page_chars`
- `PT` → `page_time`
- `i` → `idx` (char counting loop)
- `L` → `line` (render loop)
- `c` → `ch` (shimmer loop)
- `CI` → `color_idx`

- [x] Rename all variables as listed above
- [x] Verify no regressions (dry-build + visual test on lock screen)

### Phase 3: Architecture — Extract Weather Module + Stylix Colors (P2)

**Findings addressed:** #2 (weather extraction), #5 (hardcoded colors), #6 (HTTPS)

#### 3a: Extract weather service to `home/linux/weather.nix`

- [x] Create `home/linux/weather.nix` containing:
  - `systemd.user.services.weather-cache`
  - `systemd.user.timers.weather-cache`
- [x] Use `https://wttr.in/` (explicit HTTPS) in the curl command
- [x] Add `--fail` flag to avoid caching error pages: `curl -sf --max-time 10 "https://wttr.in/?format=%c+%t"`
- [x] Remove `ExecStopPost` — stale weather data is better than no data when network is flaky (finding #7)
- [x] Import `weather.nix` from `home/linux/default.nix` (or wherever linux home modules are aggregated)
- [x] Remove weather service/timer from `hyprlock.nix`
- [x] The hyprlock weather label continues reading `$XDG_RUNTIME_DIR/hyprlock-weather` (no change needed in label)

**New file structure:**

```nix
# home/linux/weather.nix
{ pkgs, ... }:
{
  systemd.user.services.weather-cache = {
    Unit.Description = "Cache weather data for hyprlock";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "weather-fetch" ''
        curl -sf --max-time 10 "https://wttr.in/?format=%c+%t" > "$XDG_RUNTIME_DIR/hyprlock-weather" 2>/dev/null
      ''}";
    };
  };

  systemd.user.timers.weather-cache = {
    Unit.Description = "Update weather cache every 10 minutes";
    Timer = {
      OnStartupSec = "0";
      OnUnitActiveSec = "10min";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
```

#### 3b: Use Stylix base16 colors

- [x] Add `config` to the module's function arguments: `{ lib, pkgs, config, ... }:`
- [ ] Define color variables from Stylix in the `let` block:

```nix
let
  c = config.lib.stylix.colors;
  colors = {
    purple = "#${c.base0E}";    # was #BB9AF7
    cyan = "#${c.base0C}";      # was #2AC3DE
    blue = "#${c.base0D}";      # was #7AA2F7
    fg = "#${c.base05}";        # was #A9B1D6
    comment = "#${c.base03}";   # was #565F89
    selection = "#${c.base02}"; # was #2F3549
    green = "#${c.base0B}";     # was #9ECE6A
    lightCyan = "#${c.base0C}"; # was #7DCFFF (closest match)
    bg = c.base00;              # was 1A1B26
    fgBright = "#${c.base06}";  # was #C0CAF5
    fgDim = "#${c.base04}";     # was #A9B1D6 (for date/weather)
  };
in
```

- [x] Replace all hardcoded hex values in shell script Pango spans with interpolated `${colors.*}` variables
- [x] Replace hardcoded `rgb()`/`rgba()` values in shape and label definitions with Stylix equivalents
- [x] Keep `stylix.targets.hyprlock.enable = false` — we still manually theme, but now the colors come from the Stylix palette
- [x] Verify colors look correct after rebuild (should be identical since the base16 scheme is Tokyo Night)

### Phase 4: Minor Hygiene (P3)

**Findings addressed:** #8 (EPOCHSECONDS fallback), #10 (transcript schema)

- [x] Remove `EPOCHSECONDS` fallback in `clawd-pgrep-check` — NixOS 25.11 ships bash 5.2, `$EPOCHSECONDS` is always available:
  - Line 9: `NOW=''${EPOCHSECONDS:-$(printf '%(%s)T' -1)}` → `NOW=$EPOCHSECONDS`
  - Line 13: same change
- [x] Add a comment documenting the `/tmp` file interface at the top of the `let` block:

```nix
  # Interface files (in $XDG_RUNTIME_DIR):
  #   clawd-jrpg-text   — word-wrapped dialogue lines (newline-separated)
  #   clawd-jrpg-user   — user's last message (single line, max 49 chars)
  #   clawd-jrpg-ts     — epoch nanoseconds when text last changed
  #   clawd-running     — pgrep cache (epoch seconds)
  #   clawd-line-{1,2,3} — rendered Pango markup for each display line
```

## Acceptance Criteria

- [ ] No files written to `/tmp` — all cache files use `$XDG_RUNTIME_DIR`
- [ ] `ls /run/user/$(id -u)/clawd-*` shows cache files when Claude is running
- [ ] Cache files cleaned up automatically on logout
- [ ] All variables in `clawd-jrpg-text` render loop have descriptive names
- [ ] Weather service lives in `home/linux/weather.nix`, imported separately
- [ ] Weather fetch uses `https://` explicitly
- [ ] Colors derived from `config.lib.stylix.colors`, not hardcoded hex
- [ ] Lock screen visual appearance unchanged (same Tokyo Night theme)
- [ ] `nixos-rebuild dry-build` passes
- [ ] Lock screen animations work: typewriter, shimmer, avatar cycling, page turns
- [ ] User message box shows clean text (no XML tags)
- [ ] LINE argument validated to `[123]` only

## Dependencies & Risks

- **Stylix color mapping**: Need to verify `base0E` = purple, `base0C` = cyan, etc. for Tokyo Night. If mapping is wrong, colors will look off. Test with `nix eval` before rebuilding.
- **`$XDG_RUNTIME_DIR` in systemd user services**: Should be set by default for user services on NixOS. Verify with `systemctl --user show-environment | grep XDG`.
- **Weather label path**: After moving weather to its own module, the hyprlock label still reads the file. Ensure the path is consistent between writer (weather.nix) and reader (hyprlock.nix).

## Sources

- PR #14: `feat/clawd-jrpg-user-label` branch
- Code review findings from 6 parallel review agents (security-sentinel, architecture-strategist, pattern-recognition-specialist, code-simplicity-reviewer, agent-native-reviewer, learnings-researcher)
- Past solution: `docs/solutions/integration-issues/nvidia-suspend-resume-prime-offload-fix.md` — confirms suspend listener must stay removed
- Pattern reference: `home/linux/ags.nix` — uses `config.lib.stylix.colors` for theming (the pattern we'll follow)
- Pattern reference: `home/linux/wallpaper.nix` — uses `writeShellScriptBin` with similar complexity (~420 lines)
