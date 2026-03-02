{ ... }:
{
  programs.waybar = {
    enable = true;
    settings = {
      mainBar = {
        layer = "top";
        position = "top";
        height = 36;
        modules-left = [ "hyprland/workspaces" "hyprland/window" ];
        modules-center = [ "clock" ];
        modules-right = [
          "mpris"
          "pulseaudio"
          "network"
          "bluetooth"
          "battery"
          "cpu"
          "tray"
        ];

        "hyprland/workspaces" = {
          format = "{icon}";
          on-click = "activate";
        };
        clock = {
          format = "{:%H:%M  %a %b %d}";
          tooltip-format = "<tt>{calendar}</tt>";
        };
        battery = {
          format = "{icon}  {capacity}%";
          format-icons = [ "" "" "" "" "" ];
          states = { warning = 30; critical = 15; };
        };
        cpu = { format = "  {usage}%"; interval = 5; };
        pulseaudio = {
          format = "{icon}  {volume}%";
          format-muted = "  muted";
          format-icons.default = [ "" "" "" ];
          on-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        };
        network = {
          format-wifi = "  {essid}";
          format-ethernet = "  {ifname}";
          format-disconnected = "  disconnected";
        };
        bluetooth = {
          format = " {status}";
          on-click = "blueman-manager";
        };
        mpris = {
          format = "{player_icon}  {title}";
          player-icons.default = "";
        };
        tray = { spacing = 10; };
      };
    };
    style = ''
      * {
        border-radius: 8px;
      }
      #workspaces button.active {
        border-bottom: 2px solid @base0D;
      }
    '';
  };
}
