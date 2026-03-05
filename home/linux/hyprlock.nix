{ lib, ... }:
{
  stylix.targets.hyprlock.enable = false;

  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        grace = 5;
        hide_cursor = true;
      };

      background = [{
        monitor = "";
        path = "~/nix-config/assets/wallpaper.png";
        blur_size = 6;
        blur_passes = 3;
        brightness = 0.7;
      }];

      image = [{
        monitor = "";
        path = "~/nix-config/assets/avatar.png";
        reload_cmd = "pgrep -x claude >/dev/null && echo ~/nix-config/assets/clawd-frame-$(($(date +%s) % 4)).png || echo ~/nix-config/assets/avatar.png";
        reload_time = 1;
        size = 120;
        rounding = -1;
        border_size = 3;
        border_color = "rgb(122, 162, 247)";
        position = "0, 200";
        halign = "center";
        valign = "center";
        shadow_passes = 1;
      }];

      label = [
        # Time
        {
          monitor = "";
          text = "$TIME";
          font_size = 64;
          font_family = "JetBrainsMono Nerd Font";
          color = "rgb(192, 202, 245)";
          position = "0, 80";
          halign = "center";
          valign = "center";
          shadow_passes = 1;
        }
        # Date
        {
          monitor = "";
          text = ''cmd[update:43200000] date +"%A, %B %d"'';
          font_size = 20;
          font_family = "JetBrainsMono Nerd Font";
          color = "rgb(169, 177, 214)";
          position = "0, 30";
          halign = "center";
          valign = "center";
          shadow_passes = 1;
        }
      ];

      input-field = lib.mkForce [{
        monitor = "";
        size = "300, 50";
        outline_thickness = 3;
        outer_color = "rgb(122, 162, 247)";
        inner_color = "rgba(30, 30, 46, 0.8)";
        font_color = "rgb(192, 202, 245)";
        rounding = 15;
        dots_size = 0.33;
        dots_spacing = 0.15;
        dots_center = true;
        fade_on_empty = true;
        placeholder_text = ''<span foreground="##a9b1d6">Password...</span>'';
        font_family = "JetBrainsMono Nerd Font";
        fail_text = "Authentication failed";
        fail_color = "rgb(247, 118, 142)";
        check_color = "rgb(158, 206, 106)";
        capslock_color = "rgb(224, 175, 104)";
        position = "0, -20";
        halign = "center";
        valign = "center";
        shadow_passes = 1;
      }];
    };
  };

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on && wallpaper-restore";
      };
      listener = [
        { timeout = 300; on-timeout = "hyprlock"; }
      ];
    };
  };
}
