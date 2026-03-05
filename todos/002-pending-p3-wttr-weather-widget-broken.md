---
status: pending
priority: p3
issue_id: "002"
tags: [waybar, weather, wttr.in]
dependencies: []
---

# Weather Widget Cannot Access wttr.in

## Problem Statement

A widget (likely waybar) is polling `wttr.in` for weather data and failing with an access error. The error appears on screen when opening the dashboard or related popups.

## Next Steps

- Identify which component is making the `wttr.in` request (grep waybar config, AGS widgets, scripts)
- Determine if `wttr.in` is blocked by network/DNS or if the endpoint is down
- Fix the request, add a fallback, or remove the weather integration if unused

## Technical Details

- **Likely affected files:** `home/linux/waybar.nix` or a custom script in `apps/`
- **GitHub issue:** #10
