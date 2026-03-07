{ pkgs, ... }:
{
  systemd.user.services.weather-cache = {
    Unit.Description = "Cache weather data for lock screen";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "weather-fetch" ''
        curl -sf --max-time 10 "https://wttr.in/?format=%c+%t" > "$XDG_RUNTIME_DIR/hyprlock-weather" 2>/dev/null
      ''}";
    };
  };

  systemd.user.timers.weather-cache = {
    Unit.Description = "Update weather cache every 10 minutes";
    Timer = {
      OnStartupSec = "0";
      OnUnitActiveSec = "10min";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
