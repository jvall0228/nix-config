{ pkgs, ... }:
let
  # The daemon is pure-stdlib python (proc scan + transcript/sqlite parse + atomic
  # write); it shells out to nothing, so no PATH setup is needed.
  daemon = "${pkgs.python3}/bin/python3 ${./agent-status-daemon.py}";

  # `agent-status` — human/JSON query tool for the published status file.
  cli = pkgs.writeShellApplication {
    name = "agent-status";
    runtimeInputs = [ pkgs.jq pkgs.coreutils pkgs.procps ];  # procps for `watch`
    text = ''
      status="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agent-status.json"

      if [ ! -s "$status" ]; then
        echo "agent-status: no status file (is the agent-status daemon running?)" >&2
        echo "  start it with: systemctl --user start agent-status" >&2
        exit 1
      fi

      case "''${1:-}" in
        --json|-j)
          jq . "$status" ;;
        --watch|-w)
          exec watch -n1 -t agent-status ;;
        "" )
          # staleness hint: warn if the daemon hasn't written in >10s
          mt=$(stat -c %Y "$status" 2>/dev/null || echo 0)
          now=$(date +%s)
          if [ $((now - mt)) -gt 10 ]; then
            echo "(status is $((now - mt))s stale — daemon may be down)" >&2
          fi
          jq -r '
            "AI agents on \(.host) — updated \(.updated)\n" +
            ([ .agents | to_entries[] |
               "  " + (.key + (" " * (10 - (.key|length)))) +
               (if .value.running
                  then "● running  (pid \(.value.pids|map(tostring)|join(",")))"
                  else "○ idle" end) +
               (if .value.lastUser
                  then "\n               you: " + (.value.lastUser|gsub("[[:cntrl:] ]+";" ")|.[0:72])
                  else "" end) +
               (if .value.lastAssistant
                  then "\n               ⤷   " + (.value.lastAssistant|gsub("[[:cntrl:] ]+";" ")|.[0:72])
                  else "" end)
             ] | join("\n"))
          ' "$status" ;;
        claude|codex|gemini|opencode)
          jq ".agents.\"$1\"" "$status" ;;
        -h|--help)
          echo "usage: agent-status [--json|-j] [--watch|-w] [<agent>]" ;;
        *)
          echo "agent-status: unknown argument '$1' (try --help)" >&2; exit 2 ;;
      esac
    '';
  };
in
{
  home.packages = [ cli ];

  systemd.user.services.agent-status = {
    Unit = {
      Description = "Publish AI-agent status (running/messages) for waybar & lock screen";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${daemon}";
      Restart = "on-failure";
      RestartSec = 2;
      # Cheap, non-critical: sacrifice first under pressure, can't hog the desktop.
      Nice = 10;
      CPUWeight = 20;
      CPUQuota = "5%";
      MemoryMax = "64M";
      IOSchedulingClass = "idle";
      OOMScoreAdjust = 500;
      NoNewPrivileges = true;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
