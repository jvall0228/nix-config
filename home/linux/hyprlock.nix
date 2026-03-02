{ lib, ... }:
{
  # Stylix auto-generates background + colors for hyprlock.
  # We only set general and input-field options here.
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        grace = 5;
        hide_cursor = true;
      };
      input-field = lib.mkForce [{
        monitor = "";
        size = "300, 50";
        outline_thickness = 3;
        fade_on_empty = true;
        placeholder_text = "Password...";
        fail_text = "Authentication failed";
        position = "0, -20";
        halign = "center";
        valign = "center";
      }];
    };
  };

  services.hypridle = {
    enable = true;
    settings = {
      general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch dpms on";
      };
      listener = [
        { timeout = 300; on-timeout = "hyprlock"; }
        { timeout = 900; on-timeout = "systemctl suspend"; }
      ];
    };
  };
}
