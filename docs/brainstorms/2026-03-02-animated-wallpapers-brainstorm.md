# Animated Wallpapers for Hyprland

**Date:** 2026-03-02
**Status:** Brainstorm

## What We're Building

A multi-tool animated wallpaper setup for Hyprland on the ThinkPad P15v Gen 3 (Nvidia Optimus). The goal is maximum visual impact with moderate GPU usage — pause/disable animations when not visible or on battery.

### Capabilities

1. **GIF/APNG wallpapers** — Already supported via swww (keep as-is)
2. **Video wallpapers** — MP4/WebM playback via mpvpaper
3. **Slideshow with transitions** — Rotate static wallpapers with swww transition effects on a timer

### Out of Scope (for now)

- Shader-based wallpapers (glpaper is stale in nixpkgs)
- linux-wallpaperengine (requires Steam + Wallpaper Engine purchase)
- Game-as-wallpaper / interactive wallpapers — Wayland's security model prevents sending regular windows to the background layer. No Hyprland window rule exists for z-order/send-to-back. The viable path would be wrapping a browser-based game in a WebKit + `gtk4-layer-shell` app (similar to how [HyprWpE](https://github.com/linuxnoodle/HyprWpE) renders web wallpapers on the background layer). Cool future project but significantly more complex. Reference: [reddit post](https://www.reddit.com/r/unixporn/comments/1o5pd8x/hyprland_running_an_idle_game_as_a_wallpaper/)

## Why This Approach

- **Multi-tool stack:** swww (GIF/APNG) + mpvpaper (video) + bash script (slideshow). Each tool does one thing well.
- **swww is already working** — no reason to replace it. It handles animated GIFs/APNGs natively and has great transition effects for slideshows.
- **mpvpaper is the standard** for video wallpapers on wlroots compositors. It wraps mpv, so any format mpv supports works.
- **All tools are in nixpkgs** — `pkgs.swww`, `pkgs.mpvpaper`. No custom packaging needed.

## Key Decisions

1. **Keep swww as primary daemon** — It handles GIF/APNG and slideshow (via scripting) well. No need for wpaperd as a separate daemon since swww transitions are already polished.

2. **Add mpvpaper for video wallpapers only** — Run it on-demand, not as a persistent daemon. Use `--auto-pause` to save resources when windows cover the wallpaper.

3. **Slideshow via bash script + swww** — A simple loop (`swww img` + `sleep`) with configurable transition effects and interval. Can be started/stopped via Hyprland keybind.

4. **Nvidia considerations:**
   - mpvpaper has known issues with Nvidia Optimus. Test with `--vo=gpu-next` and hwdec flags.
   - May need `__NV_PRIME_RENDER_OFFLOAD=1` environment variable.
   - Consider using `mpvpaper-stop` (companion tool) to fully stop playback when wallpaper is hidden.

5. **Wallpaper switching UX** — A keybind or rofi menu to switch between modes: static, GIF, video, slideshow.

## Architecture

```
Wallpaper Modes:
├── Static/GIF/APNG → swww img <file>
├── Video → mpvpaper -o "no-audio loop" "*" <video>
└── Slideshow → bash script cycling swww img with transitions

Switching:
├── Kill current wallpaper daemon/script
├── Launch new mode
└── Triggered via keybind or rofi script
```

### Files to Create/Modify

- `home/linux/hyprland.nix` — Add mpvpaper to packages, add wallpaper keybinds
- `home/linux/wallpaper.nix` (new) — Wallpaper management module with slideshow script
- `assets/wallpapers/` (new directory) — Collection of wallpapers for slideshow rotation
- `assets/videos/` (new directory) — Video wallpaper files

## Resolved Questions

- **Animation type:** Video, GIF/APNG, and slideshow — all three.
- **Priority:** Visual impact is the top priority.
- **GPU usage:** Moderate — use GPU freely but pause/disable when not visible or on battery.
- **Approach:** Multi-tool stack (swww + mpvpaper + scripting).

## Open Questions

1. **Where to source video wallpapers?** — Need to find good looping video wallpapers. Options include Wallpaper Engine Workshop (download separately), free sites like Pixabay/Pexels videos, or custom cinemagraphs.

## Additionally Resolved

- **Battery behavior:** Auto-switch to static wallpaper on battery, but keep the rofi menu available so the user can manually switch back to animated mode if desired. Check `/sys/class/power_supply/` for power state.
- **Switching UI:** Rofi menu listing wallpaper modes and available wallpapers. More discoverable than keybinds and consistent with existing rofi usage in the setup.
