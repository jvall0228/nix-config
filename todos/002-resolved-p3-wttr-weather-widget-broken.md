---
status: resolved
priority: p3
issue_id: "002"
tags: [waybar, weather, wttr.in]
dependencies: []
---

# Weather Widget Cannot Access wttr.in

## Problem Statement

A widget (likely waybar) is polling `wttr.in` for weather data and failing with an access error. The error appears on screen when opening the dashboard or related popups.

## Root Cause (diagnosed 2026-06-26)

The waybar `custom/weather` module ran `wttrbar --location auto`. Two distinct bugs:

1. **Wrong location.** wttrbar has no `auto` feature — `--location` passes its argument verbatim to wttr.in. The literal string `auto` was resolved by wttr.in to a bogus location (observed: *Campo Salles, Buenos Aires, Argentina*), so the widget displayed the wrong continent's weather.
2. **Bar-breaking panic.** `wttrbar` requires a `--location` (bare invocation panics at `src/main.rs:265`, `Option::unwrap()` on `None`) and also panics on an empty/rate-limited response from wttr.in. A panic produces no stdout, so the entire waybar `custom/weather` module rendered as an error.

## Resolution

Replaced the `exec` with a `pkgs.writeShellScript` wrapper (`home/linux/waybar.nix`) that:

- Auto-detects the real location from wttr.in's IP geolocation (`?format=%l`) — works on a moving laptop instead of a hardcoded city.
- Caches the last good JSON to `$XDG_RUNTIME_DIR/waybar-weather.json`.
- Always emits valid JSON (last cache, else `{"text":"","tooltip":"weather unavailable"}`) so a rate-limit or outage degrades gracefully instead of panicking the bar.
- Uses `--fahrenheit --mph` to match the US location and the °F already shown on the hyprlock lock screen. Flip these flags for °C/km-h.

Verified: detected location resolves to *Harrison, New Jersey, US*; the wrapper returns valid JSON on both the success and fallback paths.

## Technical Details

- **Affected file:** `home/linux/waybar.nix` (`custom/weather` module + `weatherScript`)
- **GitHub issue:** #10
