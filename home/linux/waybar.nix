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
          "idle_inhibitor"
          "custom/weather"
          "backlight"
          "pulseaudio"
          "network"
          "bluetooth"
          "battery"
          "cpu"
          "memory"
          "temperature"
          "custom/gpu"
          "disk"
          "tray"
        ];

        "hyprland/workspaces" = {
          format = "{icon}";
          on-click = "activate";
        };
        clock = {
          format = "{:%H:%M  %a %b %d}";
          tooltip-format = "<tt>{calendar}</tt>";
          on-click = "ags request toggle calendar";
        };
        battery = {
          format = "{icon}  {capacity}%";
          format-icons = [ "" "" "" "" "" ];
          states = { warning = 30; critical = 15; };
        };
        cpu = { format = "  {usage}%"; interval = 5; };
        memory = { format = "  {}%"; interval = 5; };
        temperature = {
          hwmon-path-abs = "/sys/devices/pci0000:00/0000:00:18.3";
          input-filename = "temp1_input";
          critical-threshold = 80;
          format = "  {temperatureC}°C";
          format-critical = "  {temperatureC}°C";
        };
        backlight = {
          format = "{icon}  {percent}%";
          format-icons = [ "" "" "" "" "" "" "" "" "" ];
          on-scroll-up = "brightnessctl set 5%+";
          on-scroll-down = "brightnessctl set 5%-";
        };
        idle_inhibitor = {
          format = "{icon}";
          format-icons = {
            activated = "";
            deactivated = "";
          };
        };
        disk = {
          format = "  {percentage_used}%";
          path = "/";
          interval = 60;
        };
        "custom/gpu" = {
          exec = "nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits | awk -F', ' '{printf \"  %s%% %s°C\", $1, $2}'";
          interval = 5;
          format = "{}";
          tooltip = false;
        };
        "custom/weather" = {
          exec = "wttrbar --location auto";
          return-type = "json";
          interval = 1800;
          format = "{}";
          tooltip = true;
        };
        pulseaudio = {
          format = "{icon}  {volume}%";
          format-muted = "  muted";
          format-icons.default = [ "" "" "" ];
          on-click = "ags request toggle audiomixer";
          on-middle-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          on-scroll-up = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+";
          on-scroll-down = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
        };
        network = {
          format-wifi = "  {essid}";
          format-ethernet = "  {ifname}";
          format-disconnected = "  disconnected";
          on-click = "ags request toggle network";
          on-middle-click = "sh -c 'nmcli radio wifi $(nmcli radio wifi | grep -q enabled && echo off || echo on)'";
        };
        bluetooth = {
          format = " {status}";
          on-click = "ags request toggle bluetooth";
          on-middle-click = "bluetoothctl power toggle";
        };
        mpris = {
          format = "{player_icon}  {title}";
          player-icons.default = "";
          on-click = "ags request toggle media";
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
