{ ... }:
{
  wayland.windowManager.hyprland = {
    enable = true;
    settings = {
      monitor = ",preferred,auto,1";
      "$mod" = "SUPER";

      exec-once = [ "waybar" "mako" "swww-daemon" ];

      bind = [
        "$mod, Return, exec, kitty"
        "$mod, D, exec, wofi --show drun"
        "$mod, Q, killactive,"
        "$mod, F, fullscreen,"
        "$mod, V, togglefloating,"
        "$mod, M, exit,"
        "$mod, H, movefocus, l"
        "$mod, L, movefocus, r"
        "$mod, K, movefocus, u"
        "$mod, J, movefocus, d"
        "$mod, 1, workspace, 1"
        "$mod, 2, workspace, 2"
        "$mod, 3, workspace, 3"
        "$mod, 4, workspace, 4"
        "$mod, 5, workspace, 5"
        "$mod SHIFT, 1, movetoworkspace, 1"
        "$mod SHIFT, 2, movetoworkspace, 2"
        "$mod SHIFT, 3, movetoworkspace, 3"
        "$mod SHIFT, 4, movetoworkspace, 4"
        "$mod SHIFT, 5, movetoworkspace, 5"
        '', Print, exec, grim -g "$(slurp)" - | wl-copy''
      ];

      env = [ "XCURSOR_SIZE,24" ];
      general = { gaps_in = 5; gaps_out = 10; border_size = 2; };
      input = { kb_layout = "us"; follow_mouse = 1; touchpad.natural_scroll = true; };
    };
  };
}
