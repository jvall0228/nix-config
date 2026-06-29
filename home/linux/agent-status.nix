{ pkgs, unstable, ... }:
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

  # ---------------------------------------------------------------------------
  # agent-spawn — launch a preset agent session in its own tmux session.
  # ---------------------------------------------------------------------------
  # A preset bundles an agent with whether bypass-permissions is on (+ optional
  # model). The per-harness *spelling* of bypass and how a prompt is passed live
  # in the launcher below, not in preset data. Bare preset name (e.g. `claude`)
  # is the bypass-on default; `<agent>-safe` is the non-bypass opt-out.
  spawnPresets = {
    claude        = { agent = "claude";   bypass = true; };
    claude-safe   = { agent = "claude";   bypass = false; };
    codex         = { agent = "codex";    bypass = true; };
    codex-safe    = { agent = "codex";    bypass = false; };
    opencode      = { agent = "opencode"; bypass = true; };
    opencode-safe = { agent = "opencode"; bypass = false; };
  };
  spawnPresetsJson = pkgs.writeText "agent-spawn-presets.json"
    (builtins.toJSON spawnPresets);

  # Absolute store paths so a spawned agent resolves regardless of the (possibly
  # stale) PATH baked into an already-running tmux server.
  claudeBin = "${unstable.claude-code}/bin/claude";
  codexBin = "${unstable.codex}/bin/codex";
  opencodeBin = "${unstable.opencode}/bin/opencode";

  spawnCli = pkgs.writeShellApplication {
    name = "agent-spawn";
    runtimeInputs = [ pkgs.tmux pkgs.jq pkgs.coreutils ];
    text = ''
      presets=${spawnPresetsJson}

      usage() {
        printf '%s\n' \
          "usage: agent-spawn <preset> [dir] [prompt]" \
          "       agent-spawn --list      # show available presets" \
          "" \
          "Spawns the preset's agent in its own detached tmux session (bypass" \
          "baked into the preset) and prints the session name. Attach later with:" \
          "  tmux attach -t <name>" >&2
      }

      case "''${1:-}" in
        -h|--help) usage; exit 0 ;;
        --list)
          jq -r 'to_entries[]
                 | "  \(.key)" + (" " * (16 - (.key | length)))
                   + "-> \(.value.agent)  (bypass=\(.value.bypass))"' "$presets"
          exit 0 ;;
        "") usage; exit 2 ;;
      esac

      preset="$1"
      dir="''${2:-$PWD}"
      prompt="''${3:-}"

      if ! row=$(jq -c -e --arg p "$preset" '.[$p] // empty' "$presets"); then
        echo "agent-spawn: unknown preset '$preset' (try: agent-spawn --list)" >&2
        exit 2
      fi
      agent=$(jq -r '.agent' <<<"$row")
      bypass=$(jq -r '.bypass' <<<"$row")
      model=$(jq -r '.model // ""' <<<"$row")

      if [ ! -d "$dir" ]; then
        echo "agent-spawn: directory '$dir' does not exist" >&2
        exit 2
      fi

      case "$agent" in
        claude)   bin=${claudeBin} ;;
        codex)    bin=${codexBin} ;;
        opencode) bin=${opencodeBin} ;;
        *) echo "agent-spawn: preset '$preset' names unknown agent '$agent'" >&2
           exit 2 ;;
      esac

      # Build the agent argv and any tmux -e env. Prompt and dir are passed as
      # distinct argv elements (never interpolated into a shell string), so they
      # cannot word-split or inject shell commands at spawn time.
      argv=()
      envs=()
      if [ -n "$model" ]; then argv+=( --model "$model" ); fi
      case "$agent" in
        claude)
          if [ "$bypass" = true ]; then argv+=( --dangerously-skip-permissions ); fi
          # `--` so a prompt whose first token starts with `-` is taken as the
          # seed prompt, not parsed as a claude option.
          if [ -n "$prompt" ]; then argv+=( -- "$prompt" ); fi
          ;;
        codex)
          if [ "$bypass" = true ]; then argv+=( --dangerously-bypass-approvals-and-sandbox ); fi
          # `--` so a dash-leading prompt is taken as the prompt, not a codex flag.
          if [ -n "$prompt" ]; then argv+=( -- "$prompt" ); fi
          ;;
        opencode)
          # opencode's bypass is an env var, not a flag, so unlike claude/codex the
          # safe path must actively PIN it: set the session-level value either way
          # so an ambient OPENCODE_PERMISSION in the tmux server's global env can't
          # silently flip a -safe session to allow-all (tmux merges the global env
          # into every new session; the session-level -e value wins). This keeps
          # opencode-safe a real non-bypass opt-out (R7); it is not a sandbox.
          if [ "$bypass" = true ]; then
            envs+=( -e 'OPENCODE_PERMISSION={"*":"allow"}' )
          else
            envs+=( -e 'OPENCODE_PERMISSION={"*":"ask"}' )
          fi
          if [ -n "$prompt" ]; then argv+=( --prompt "$prompt" ); fi
          ;;
      esac

      # Predictable, collision-safe session name: agent-<harness>-<dir-basename>.
      base=$(basename -- "$dir")
      slug=$(printf '%s' "$base" | tr -c 'A-Za-z0-9_-' '-' | tr -s '-')
      slug=''${slug#-}
      slug=''${slug%-}
      if [ -z "$slug" ]; then slug=root; fi
      name="agent-$agent-$slug"
      if tmux has-session -t "=$name" 2>/dev/null; then
        i=2
        while tmux has-session -t "=$name-$i" 2>/dev/null; do i=$((i + 1)); done
        name="$name-$i"
      fi

      # Launch detached; pass the agent argv directly (tmux runs it with no shell
      # when given as multiple args after --). Keep the pane after the agent exits
      # via tmux-native remain-on-exit.
      tmux new-session -d -s "$name" -c "$dir" "''${envs[@]}" -- "$bin" "''${argv[@]}"
      tmux set-option -w -t "$name" remain-on-exit on 2>/dev/null || true

      # opencode's --prompt pre-fills but may not auto-submit; nudge once after the
      # TUI settles (detached, so the parent returns immediately). A bare Enter
      # only submits whatever is in the input box, so a double-fire is harmless.
      if [ "$agent" = opencode ] && [ -n "$prompt" ]; then
        ( sleep 4; tmux send-keys -t "=$name" Enter ) >/dev/null 2>&1 &
      fi

      printf '%s\n' "$name"
    '';
  };
in
{
  home.packages = [ cli spawnCli ];

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
