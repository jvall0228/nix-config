{ pkgs, ... }:
let
  # Resilient weather fetch for the waybar custom/weather module.
  # wttrbar needs an explicit --location and panics on an empty/rate-limited
  # response (which previously broke the whole bar). The old config passed the
  # literal string "auto", so wttr.in resolved it to a bogus location. Instead:
  # auto-detect the location from wttr.in's IP geolocation (works on a moving
  # laptop), cache the last good JSON, and always emit valid JSON so the bar
  # never breaks.
  weatherScript = pkgs.writeShellScript "waybar-weather" ''
    cache="$XDG_RUNTIME_DIR/waybar-weather.json"
    loc=$(${pkgs.curl}/bin/curl -sf --max-time 10 "https://wttr.in/?format=%l" 2>/dev/null)
    if [ -n "$loc" ]; then
      out=$(${pkgs.wttrbar}/bin/wttrbar --location "$loc" --fahrenheit --mph 2>/dev/null)
      case "$out" in
        '{'*) echo "$out" | tee "$cache"; exit 0 ;;
      esac
    fi
    if [ -s "$cache" ]; then
      cat "$cache"
    else
      echo '{"text":"","tooltip":"weather unavailable"}'
    fi
  '';

  # Live AI-agent indicator. Consumes the agent-status daemon's JSON; emits empty
  # text (waybar auto-hides the module) when nothing is running. waybar polls it
  # every 2s (see the module's interval); the daemon never signals the bar.
  agentScript = pkgs.writeShellScript "waybar-agent" ''
    status="$XDG_RUNTIME_DIR/agent-status.json"
    # Shape-tolerant: a missing/invalid file or wrong-shaped JSON yields no output,
    # and the shell fallback below always emits a valid waybar JSON object.
    out=$(${pkgs.jq}/bin/jq -c '
      def esc: gsub("&";"&amp;") | gsub("<";"&lt;") | gsub(">";"&gt;");
      [ (.agents? // {}) | objects | to_entries[] | select(.value.running == true) ] as $live
      | if ($live|length) == 0 then { text: "" }
        else {
          text: ("󰚩  " + (if ($live|length) > 1
                            then "\($live|length) agents"
                            else $live[0].key end)),
          class: "running",
          tooltip: ( $live | map(
              "● \(.key)  (pid \(.value.pids|map(tostring)|join(",")))"
              + (if .value.lastAssistant
                   then "\n   " + (.value.lastAssistant | gsub("[[:cntrl:] ]+"; " ") | .[0:90] | esc)
                   else "" end)
            ) | join("\n") )
        } end
    ' "$status" 2>/dev/null)
    case "$out" in
      "{"*) printf '%s\n' "$out" ;;
      *)    echo '{"text":""}' ;;
    esac
  '';

  # CUA DRIVING indicator. Red pill while an agent holds the real-desktop seat
  # (R13); empty text (auto-hidden) otherwise. Polled at 1s — unlike the agent
  # pill, "an agent is driving my cursor" is latency-relevant. Reads the cua
  # daemon's `.driving` flag; the flag flips to false on panic/release, so the
  # pill clears within a tick (AE3).
  cuaScript = pkgs.writeShellScript "waybar-cua" ''
    status="$XDG_RUNTIME_DIR/cua-status.json"
    out=$(${pkgs.jq}/bin/jq -c '
      if (.agentMode.active == true) then {
        text: ("󰍁  AGENT MODE" + (if .driving then "  󰷢 " + (.lease.holder // "agent") else "" end)),
        class: "agentlock",
        tooltip: ("agent-mode lock — desktop staged on \(.agentMode.stage); agents retain full computer-use access" + (if .driving then "\n▶ \(.lease.holder) driving \(.lease.target)" else "" end))
      } elif (.driving == true) then {
        text: ("󰷢  " + (.lease.holder // "agent") + (if .lease.locked then "  " else "" end)),
        class: (if .lease.locked then "locked" else "driving" end),
        tooltip: ("driving \(.lease.target) — \(.lease.kind)")
      } else { text: "" } end
    ' "$status" 2>/dev/null)
    case "$out" in
      "{"*) printf '%s\n' "$out" ;;
      *)    echo '{"text":""}' ;;
    esac
  '';

  # Live hover tooltip for the system button. The inline cpu/mem/temp/disk
  # readouts moved into the dashboard, so this restores an at-a-glance peek
  # without re-cluttering the bar. Deliberately uses only cheap /proc + sysfs
  # reads (no nvidia-smi) so it never wakes the runtime-suspended dGPU. The icon
  # itself stays in the module's static `format`; the script only fills tooltip.
  systemBtnScript = pkgs.writeShellScript "waybar-system" ''
    load=$(${pkgs.coreutils}/bin/cut -d' ' -f1 /proc/loadavg)
    mem=$(${pkgs.procps}/bin/free | ${pkgs.gawk}/bin/awk '/Mem:/ {printf "%.0f", $3/$2*100}')
    temp=$(${pkgs.coreutils}/bin/cat /sys/devices/pci0000:00/0000:00:18.3/hwmon/hwmon*/temp1_input 2>/dev/null \
            | ${pkgs.coreutils}/bin/head -1 | ${pkgs.gawk}/bin/awk '{printf "%.0f", $1/1000}')
    disk=$(${pkgs.coreutils}/bin/df / | ${pkgs.gawk}/bin/awk 'NR==2 {gsub("%","",$5); print $5}')
    printf '{"text":"","tooltip":"Load %s   RAM %s%%   CPU %s°C   Disk %s%%"}\n' \
      "''${load:-?}" "''${mem:-?}" "''${temp:-?}" "''${disk:-?}"
  '';
in
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
          "custom/cua"
          "custom/agent"
          "mpris"
          "idle_inhibitor"
          "custom/weather"
          "backlight"
          "pulseaudio"
          "network"
          "bluetooth"
          "battery"
          "custom/system"
          "tray"
        ];

        # Single system-info button — opens the AGS dashboard popup (system
        # stats, power, quick settings, session actions); same target as the
        # Super+A keybind. The CPU/RAM/temp/GPU/disk readouts live in that panel
        # now instead of cluttering the bar inline. (Those module definitions are
        # retained below but unreferenced, so they don't render or poll.)
        "custom/system" = {
          exec = "${systemBtnScript}";
          return-type = "json";
          interval = 5;
          format = "󰓅";
          on-click = "ags request toggle dashboard";
          tooltip = true;
        };

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
          format-icons = [ "󰁺" "󰁼" "󰁾" "󰂀" "󰁹" ];
          states = { warning = 30; critical = 15; };
        };
        cpu = { format = "󰻠  {usage}%"; interval = 5; };
        memory = { format = "󰍛  {}%"; interval = 5; };
        temperature = {
          # k10temp (AMD CPU, Tctl). hwmon-path-abs must point at the *hwmon*
          # folder; waybar globs the hwmonN subdir + input-filename. The PCI
          # function 0000:00:18.3 is stable across boots, so this survives the
          # hwmonN renumbering. (Previously missing the /hwmon segment, which
          # left the CPU-temp module silently empty.)
          hwmon-path-abs = "/sys/devices/pci0000:00/0000:00:18.3/hwmon";
          input-filename = "temp1_input";
          critical-threshold = 80;
          format = "󰔏  {temperatureC}°C";
          format-critical = "󰔏  {temperatureC}°C";
        };
        backlight = {
          format = "{icon}  {percent}%";
          format-icons = [ "󰃛" "󰃜" "󰃝" "󰃞" "󰃟" "󰃠" "󰃡" ];
          on-scroll-up = "brightnessctl set 5%+";
          on-scroll-down = "brightnessctl set 5%-";
        };
        idle_inhibitor = {
          format = "{icon}";
          format-icons = {
            activated = "󰅶";
            deactivated = "󰒲";
          };
        };
        disk = {
          format = "󰋊  {percentage_used}%";
          path = "/";
          interval = 60;
        };
        "custom/gpu" = {
          exec = "nvidia-smi --query-gpu=utilization.gpu,temperature.gpu --format=csv,noheader,nounits | awk -F', ' '{printf \"󰢮  %s%%  󰔏 %s°C\", $1, $2}'";
          interval = 5;
          format = "{}";
          tooltip = false;
        };
        "custom/weather" = {
          exec = "${weatherScript}";
          return-type = "json";
          interval = 1800;
          format = "{}";
          tooltip = true;
        };
        "custom/cua" = {
          exec = "${cuaScript}";
          return-type = "json";
          interval = 1;
          format = "{}";
          tooltip = true;
          max-length = 30;
        };
        "custom/agent" = {
          exec = "${agentScript}";
          return-type = "json";
          # Poll the daemon's JSON every 2s. Deliberately decoupled from the
          # daemon (no signal/pkill) so the status producer can never destabilise
          # the bar; 2s latency is irrelevant for a glanceable indicator.
          interval = 2;
          format = "{}";
          tooltip = true;
          max-length = 40;
        };
        pulseaudio = {
          format = "{icon}  {volume}%";
          format-muted = "󰝟  muted";
          format-icons.default = [ "󰕿" "󰖀" "󰕾" ];
          on-click = "ags request toggle audiomixer";
          on-middle-click = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          on-scroll-up = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+";
          on-scroll-down = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
        };
        network = {
          format-wifi = "󰖩  {essid}";
          format-ethernet = "󰈀  {ifname}";
          format-disconnected = "󰖪  disconnected";
          on-click = "ags request toggle network";
          on-middle-click = "sh -c 'nmcli radio wifi $(nmcli radio wifi | grep -q enabled && echo off || echo on)'";
        };
        bluetooth = {
          format = "󰂯  {status}";
          on-click = "ags request toggle bluetooth";
          on-middle-click = "bluetoothctl power toggle";
        };
        mpris = {
          format = "{player_icon}  {title}";
          player-icons.default = "󰎈";
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
      /* AI-agent indicator: purple pill (the Claude accent) when an agent runs;
         waybar auto-hides it when the module emits empty text. */
      #custom-agent.running {
        color: @base00;
        background-color: @base0E;
        padding: 0 12px;
        margin: 0 6px;
      }
      /* CUA DRIVING indicator: red alarm pill (base08) while an agent drives the
         real desktop; auto-hidden otherwise. `.locked` carries a lock glyph in
         its text to signal that your physical input is parked. */
      #custom-cua.driving,
      #custom-cua.locked {
        color: @base00;
        background-color: @base08;
        padding: 0 12px;
        margin: 0 6px;
      }
      /* AGENT-MODE LOCK indicator (R17): amber pill (base0A) while the screen is
         "locked" but agents still drive your real desktop off-screen. Distinct
         from the red driving alarm so the porous-lock state reads at a glance. */
      #custom-cua.agentlock {
        color: @base00;
        background-color: @base0A;
        padding: 0 12px;
        margin: 0 6px;
      }
      /* System-info button: a single glyph that toggles the AGS dashboard popup.
         Styled like the other clickable bar items (plain icon) with a @base02
         hover affordance, matching the AGS button convention. */
      #custom-system {
        padding: 0 10px;
        margin: 0 2px;
      }
      #custom-system:hover {
        background-color: @base02;
        border-radius: 8px;
      }
    '';
  };
}
