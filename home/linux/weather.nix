{ pkgs, ... }:
{
  systemd.user.services.weather-cache = {
    Unit.Description = "Cache weather data for lock screen";
    Service = {
      Type = "oneshot";
      # Best-effort cache: retry to ride out the boot-time network race, write
      # atomically so the lock screen never reads a half-written file, and always
      # exit 0 so a transient outage never leaves the unit in a failed state.
      ExecStart = "${pkgs.writeShellScript "weather-fetch" ''
        tmp="$XDG_RUNTIME_DIR/hyprlock-weather.tmp"
        for attempt in 1 2 3 4 5; do
          if ${pkgs.curl}/bin/curl -sf --max-time 10 \
            "https://wttr.in/?format=%c+%t" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
            mv "$tmp" "$XDG_RUNTIME_DIR/hyprlock-weather"
            exit 0
          fi
          sleep 5
        done
        rm -f "$tmp"
        exit 0
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
