{ pkgs, ... }:
let
  # Cycle the lock screen's JRPG box through the running agent sessions. Bound to a
  # lock-enabled (bindl) key so it works while hyprlock is up — hyprlock sends normal
  # keys to the password field, but Hyprland still services bindl binds when locked.
  # It bumps the session cursor that clawd-jrpg-text reads, then ages that cache's
  # mtime so the next 30ms render re-reads immediately (instead of waiting ~1s).
  clawd-session-cycle = pkgs.writeShellScript "clawd-session-cycle" ''
    D="$XDG_RUNTIME_DIR"
    STATUS="$D/agent-status.json"
    TOTAL=$(${pkgs.jq}/bin/jq -r '.hyprlock.sessions // [] | length' "$STATUS" 2>/dev/null)
    [ -z "$TOTAL" ] && exit 0
    case "$TOTAL" in *[!0-9]*) exit 0 ;; esac
    [ "$TOTAL" -le 1 ] && exit 0   # nothing to cycle through
    CUR=$(cat "$D/clawd-session-cursor" 2>/dev/null); [ -z "$CUR" ] && CUR=0
    case "$CUR" in *[!0-9-]*) CUR=0 ;; esac
    case "''${1:-next}" in
      prev) CUR=$((CUR - 1)) ;;
      *)    CUR=$((CUR + 1)) ;;
    esac
    CUR=$(( (CUR % TOTAL + TOTAL) % TOTAL ))
    printf '%s' "$CUR" > "$D/clawd-session-cursor"
    touch -d @0 "$D/clawd-jrpg-text" 2>/dev/null || true
  '';
in
{
  home.packages = with pkgs; [
    kitty
    rofi
    rofi-emoji
    hyprlock
    hypridle
    wlogout
    cliphist
    wl-clipboard
    grim
    slurp
    brightnessctl
    playerctl
    nautilus
    wl-screenrec
    hyprpicker
    wttrbar
    wtype  # needed by rofi-emoji to type emoji
  ];

  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      monitor = ",preferred,auto,2";
      "$mod" = "SUPER";

      exec-once = [
        # Make WAYLAND_DISPLAY/HYPRLAND_INSTANCE_SIGNATURE visible to systemd
        # user services (the cua daemon's grim/hyprctl). The daemon also
        # self-discovers these, so this is belt-and-suspenders for restarts.
        "systemctl --user import-environment WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP"
        "waybar"
        # AGS runs as a supervised systemd user service (home/linux/ags.nix) so
        # its popups self-heal on crash; it's software-rendered there to work
        # around the hybrid-GPU layer-shell paint issue.
        "wallpaper-init"
        "wallpaper-battery-monitor"
        "/run/current-system/sw/bin/polkit-kde-agent-1"
        "wl-paste --type text --watch cliphist store"
        "wl-paste --type image --watch cliphist store"
      ];

      env = [
        "XCURSOR_SIZE,24"
        "ELECTRON_OZONE_PLATFORM_HINT,auto"
        "QT_QPA_PLATFORM,wayland"
        "QT_WAYLAND_DISABLE_WINDOWDECORATION,1"
      ];

      bind = [
        "$mod, Return, exec, kitty"
        "$mod, D, exec, rofi -show drun"
        "$mod, SPACE, exec, walker"
        "$mod, Q, killactive,"
        "$mod, F, fullscreen,"
        "$mod, V, togglefloating,"
        "$mod, M, exec, wlogout"
        "$mod SHIFT, L, exec, hyprlock"
        # Agent-mode lock (R17): lock the screen but keep agents driving the real
        # desktop (staged off-screen behind a curtain). Unlock with Super+Shift+U
        # (a bind live inside the agentlock submap) or the panic chord.
        "$mod CTRL, L, exec, cua agent-mode on"
        "$mod, W, exec, sh -c 'rofi -show wallpaper -modi \"wallpaper:wallpaper-menu\" -show-icons -theme-str \"listview { columns: 3; lines: 3; }\" -theme-str \"element-icon { size: 150px; }\"'"
        "$mod, N, exec, ags request toggle notifications"
        "$mod, A, exec, ags request toggle dashboard"
        "$mod SHIFT, R, exec, sh -c 'if pgrep -x wl-screenrec > /dev/null; then pkill -x wl-screenrec; else mkdir -p ~/Videos && wl-screenrec -f ~/Videos/recording-$(date +%Y%m%d-%H%M%S).mp4; fi'"
        "$mod SHIFT, C, exec, hyprpicker -a"
        "ALT, Tab, exec, rofi -show window"
        "$mod, period, exec, rofi -show emoji -modi emoji"
        "SUPER, C, exec, sh -c 'cliphist list | rofi -dmenu | cliphist decode | wl-copy'"
        "$mod, H, movefocus, l"
        "$mod, L, movefocus, r"
        "$mod, K, movefocus, u"
        "$mod, J, movefocus, d"
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod, 6, workspace, 6"
        "$mod, 7, workspace, 7"
        "$mod, 8, workspace, 8"
        "$mod, 9, workspace, 9"
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        "$mod SHIFT, 6, movetoworkspace, 6"
        "$mod SHIFT, 7, movetoworkspace, 7"
        "$mod SHIFT, 8, movetoworkspace, 8"
        "$mod SHIFT, 9, movetoworkspace, 9"
        "$mod SHIFT, S, exec, sh -c 'rofi -show capture -modi \"capture:capture-menu\"'"
      ];

      bindl = [
        # CUA panic (R14): hard-stop all agent input, seat back to you. `bindl`
        # so it fires even while locked; on the keyboard, which the cua lockout
        # deliberately never disables so this key can't be deadlocked.
        "$mod SHIFT, Escape, exec, cua-panic"
        # Cycle the lock screen's JRPG box through running agent sessions (works while
        # locked). bracketright = next, bracketleft = previous.
        "$mod, bracketright, exec, ${clawd-session-cycle} next"
        "$mod, bracketleft, exec, ${clawd-session-cycle} prev"
        ", XF86AudioRaiseVolume, exec, sh -c 'wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ && ags request osd volume'"
        ", XF86AudioLowerVolume, exec, sh -c 'wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- && ags request osd volume'"
        ", XF86AudioMute, exec, sh -c 'wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle && ags request osd volume'"
        ", XF86AudioMicMute, exec, sh -c 'wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle && ags request osd mic'"
        ", XF86AudioPlay, exec, playerctl play-pause"
        ", XF86AudioNext, exec, playerctl next"
        ", XF86AudioPrev, exec, playerctl previous"
      ];

      binde = [
        ", XF86MonBrightnessUp, exec, sh -c 'brightnessctl set 5%+ && ags request osd brightness'"
        ", XF86MonBrightnessDown, exec, sh -c 'brightnessctl set 5%- && ags request osd brightness'"
      ];

      # Agent-mode lock curtain (R17): force the cua-curtain window fullscreen and
      # chromeless so it cleanly covers the physical output while the desktop is
      # staged off-screen.
      windowrulev2 = [
        "fullscreen, class:^(cua-curtain)$"
        "noborder, class:^(cua-curtain)$"
        "noanim, class:^(cua-curtain)$"
      ];

      general = { gaps_in = 5; gaps_out = 10; border_size = 2; };
      input = { kb_layout = "us"; follow_mouse = 1; sensitivity = 0.5; touchpad.natural_scroll = true; };

      decoration.shadow.enabled = false;

      animations = {
        enabled = true;
        bezier = [
          "ease, 0.25, 0.1, 0.25, 1.0"
          "easeOut, 0.0, 0.0, 0.2, 1.0"
        ];
        animation = [
          "windows, 1, 4, ease, slide"
          "windowsOut, 1, 4, easeOut, slide"
          "fade, 1, 3, ease"
          "workspaces, 1, 3, ease, slide"
        ];
      };

      misc = {
        vfr = true;
        disable_hyprland_logo = true;
        disable_splash_rendering = true;
        # Let a fresh hyprlock re-attach to an orphaned session lock if the
        # locker ever dies without unlocking (a "lockdead" state) — otherwise the
        # session is stuck locked with no client to authenticate against. Cheap
        # resilience for the cua agent-mode/hyprlock interplay (R17).
        allow_session_lock_restore = true;
      };

};

    # Agent-mode lock submap (R17). While active, EVERY normal keybind is gone —
    # only the panic chord and graceful-unlock remain, so a passerby's keyboard
    # is inert even though the keyboard device itself is never disabled (the
    # panic chord must always be able to fire). The cua daemon enters this with
    # `hyprctl dispatch submap agentlock` on lock and `submap reset` on unlock.
    # Appended raw because submaps are positional and don't map to the settings
    # attrset cleanly.
    extraConfig = ''
      submap = agentlock
      bind = SUPER SHIFT, Escape, exec, cua-panic
      bind = SUPER SHIFT, U, exec, cua agent-mode off
      submap = reset
    '';
  };
}
