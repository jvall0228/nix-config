{ pkgs, ... }:
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
        "waybar"
        "ags run"
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
      };

};
  };
}
