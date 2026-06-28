{ pkgs, lib, ... }:
let
  # The daemon is pure-stdlib python3; it shells out to hyprctl/grim/ydotool/
  # wtype, so it needs those on PATH (the systemd user env doesn't inherit the
  # graphical session's PATH). hyprctl ships in the hyprland package.
  daemonPath = lib.makeBinPath [
    pkgs.hyprland   # hyprctl
    pkgs.grim
    pkgs.ydotool
    pkgs.wtype
    pkgs.jq
    pkgs.coreutils
    pkgs.systemd    # systemctl (panic verb)
    pkgs.procps
  ];
  daemon = "${pkgs.python3}/bin/python3 ${./cua-daemon.py}";

  # Panic: hard-stop all agent input and hand the seat back (R14). Minimal by
  # design — see cua-panic.sh. Bound to a key in hyprland.nix via `exec, cua-panic`.
  cua-panic = pkgs.writeShellApplication {
    name = "cua-panic";
    runtimeInputs = [ pkgs.systemd pkgs.procps pkgs.coreutils pkgs.libnotify pkgs.hyprland ];
    text = builtins.readFile ./cua-panic.sh;
  };

  # The agent-mode lock curtain (R17). Spawned fullscreen by the daemon on the
  # physical output; a pure-display status board (no stdin). See cua-curtain.sh.
  cua-curtain = pkgs.writeShellApplication {
    name = "cua-curtain";
    runtimeInputs = [ pkgs.jq pkgs.coreutils pkgs.ncurses ];
    text = builtins.readFile ./cua-curtain.sh;
  };

  # Idle-lock router (R17): hypridle's on-timeout runs this instead of hyprlock —
  # it locks into porous agent-mode when any agent is running, else a real
  # hyprlock. Self-contained (cua + hyprlock + jq in its PATH). See hyprlock.nix.
  cua-idle-lock = pkgs.writeShellApplication {
    name = "cua-idle-lock";
    runtimeInputs = [ cli pkgs.hyprlock pkgs.hyprland pkgs.jq pkgs.coreutils ];
    text = builtins.readFile ./cua-idle-lock.sh;
  };

  # `cua` — the harness-agnostic CLI every agent shells out to. Read-only verbs
  # touch the published JSON / grim directly; stateful verbs send one JSON line
  # to the daemon's Unix socket and print the reply.
  cli = pkgs.writeShellApplication {
    name = "cua";
    runtimeInputs = [ pkgs.jq pkgs.coreutils pkgs.socat pkgs.procps ];
    text = ''
      runtime="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      status="$runtime/cua-status.json"
      sock="$runtime/cua.sock"
      deftarget="$runtime/cua.target"
      export YDOTOOL_SOCKET="$runtime/.ydotool_socket"

      die() { echo "cua: $*" >&2; exit 1; }

      # send <json> : print daemon reply, exit-code follows reply.ok
      send() {
        local resp
        resp=$(printf '%s\n' "$1" | socat -t6 - "UNIX-CONNECT:$sock" 2>/dev/null) \
          || die "daemon unreachable — is it up? (systemctl --user status cua)"
        printf '%s\n' "$resp" | jq .
        printf '%s' "$resp" | jq -e '.ok' >/dev/null 2>&1
      }

      default_target() { cat "$deftarget" 2>/dev/null || echo real; }

      # TARGET is an optional LEADING positional ONLY — never a value mid-args,
      # so `cua click --x 100` can't mistake "100" for the target. Everything
      # after goes to REST[] for the per-verb option loop.
      TARGET=""; REST=()
      grab_target() {
        TARGET=""; REST=()
        case "''${1:-}" in
          ""|-*) : ;;                 # leading flag/empty -> no target
          *) TARGET="$1"; shift ;;     # leading word -> target
        esac
        REST=("$@")
      }

      cmd="''${1:-}"; shift || true
      case "$cmd" in
        status)
          if [ ! -s "$status" ]; then
            die "no status file — is the cua daemon running? (systemctl --user status cua)"
          fi
          case "''${1:-}" in
            --json|-j) jq . "$status" ;;
            --watch|-w) exec watch -n1 -t cua status ;;
            "")
              mt=$(stat -c %Y "$status" 2>/dev/null || echo 0)
              now=$(date +%s)
              if [ $((now - mt)) -gt 10 ]; then
                echo "(status is $((now - mt))s stale — daemon may be down)" >&2
              fi
              jq -r '
                "cua on \(.host) — \(.updated)" ,
                (if .lease then
                   "  seat: \(.lease.holder) → \(.lease.target) (\(.lease.kind)\(if .lease.locked then ", locked" else "" end))"
                 else "  seat: free" end) ,
                (if (.queue|length) > 0 then "  queue: \(.queue|join(", "))" else empty end) ,
                "  targets:" ,
                (.targets[] | "    \(.id)  [\(.kind)]  \(.output)\(if .sandbox then "  (sandbox)" else "" end)")
              ' "$status" ;;
            *) die "unknown status flag '$1'" ;;
          esac ;;

        see)
          grab_target "$@"
          local_t="''${TARGET:-$(default_target)}"
          region=""; out=""; tree=false
          i=0
          while [ "$i" -lt "''${#REST[@]}" ]; do
            case "''${REST[$i]}" in
              --region) i=$((i+1)); region="''${REST[$i]:-}"; [ -n "$region" ] || die "--region needs a value (e.g. \"0,0 200x200\")" ;;
              --out|-o)  i=$((i+1)); out="''${REST[$i]:-}";    [ -n "$out" ]    || die "--out needs a value" ;;
              --tree)    tree=true ;;
              *) die "unknown see option: ''${REST[$i]}" ;;
            esac
            i=$((i+1))
          done
          send "$(jq -nc --arg t "$local_t" --arg r "$region" --arg o "$out" --argjson tree "$tree" \
                  '{verb:"see",target:$t} + (if $r!="" then {region:$r} else {} end) + (if $o!="" then {out:$o} else {} end) + (if $tree then {tree:true} else {} end)')" ;;

        acquire)
          [ "$#" -ge 1 ] || die "usage: cua acquire <target>"
          send "$(jq -nc --arg t "$1" '{verb:"acquire",target:$t}')" ;;

        release)
          send "$(jq -nc '{verb:"release"}')" ;;

        grant)
          [ "$#" -ge 1 ] || die "usage: cua grant <agent> [target] [--lock]"
          agent="$1"; shift
          gt="real"; lock=false
          while [ "$#" -gt 0 ]; do
            case "$1" in --lock) lock=true ;; -*) : ;; *) gt="$1" ;; esac; shift
          done
          tok=$(cat "$runtime/cua.grant.token" 2>/dev/null || true)
          send "$(jq -nc --arg a "$agent" --arg t "$gt" --argjson l "$lock" --arg k "$tok" '{verb:"grant",agent:$a,target:$t,lock:$l,token:$k}')" ;;

        revoke)
          tok=$(cat "$runtime/cua.grant.token" 2>/dev/null || true)
          if [ "$#" -ge 1 ]; then
            send "$(jq -nc --arg a "$1" --arg k "$tok" '{verb:"revoke",agent:$a,token:$k}')"
          else
            send "$(jq -nc --arg k "$tok" '{verb:"revoke",token:$k}')"
          fi ;;

        click)
          grab_target "$@"
          button="left"; x=""; y=""
          i=0
          while [ "$i" -lt "''${#REST[@]}" ]; do
            case "''${REST[$i]}" in
              --button|-b) i=$((i+1)); button="''${REST[$i]:-}"; [ -n "$button" ] || die "--button needs a value" ;;
              --x) i=$((i+1)); x="''${REST[$i]:-}"; [ -n "$x" ] || die "--x needs a value" ;;
              --y) i=$((i+1)); y="''${REST[$i]:-}"; [ -n "$y" ] || die "--y needs a value" ;;
              *) die "unknown click option: ''${REST[$i]}" ;;
            esac
            i=$((i+1))
          done
          req=$(jq -nc --arg b "$button" '{verb:"click",button:$b}')
          [ -n "$TARGET" ] && req=$(printf '%s' "$req" | jq -c --arg t "$TARGET" '. + {target:$t}')
          if [ -n "$x" ] || [ -n "$y" ]; then
            { [ -n "$x" ] && [ -n "$y" ]; } || die "click needs BOTH --x and --y, or neither"
            req=$(printf '%s' "$req" | jq -c --argjson x "$x" --argjson y "$y" '. + {x:$x,y:$y}')
          fi
          send "$req" ;;

        type)
          # TARGET (optional) appears before a literal '--'; everything after is
          # the text. Avoids grab_target stealing a text word as the target.
          tgt=""; collected=0; text_parts=()
          for a in "$@"; do
            if [ "$collected" -eq 1 ]; then text_parts+=("$a")
            elif [ "$a" = "--" ]; then collected=1
            else case "$a" in -*) : ;; *) [ -z "$tgt" ] && tgt="$a" ;; esac
            fi
          done
          [ "$collected" -eq 1 ] || die "usage: cua type [target] -- <text>"
          text="''${text_parts[*]:-}"
          req=$(jq -nc --arg s "$text" '{verb:"type",text:$s}')
          [ -n "$tgt" ] && req=$(printf '%s' "$req" | jq -c --arg t "$tgt" '. + {target:$t}')
          send "$req" ;;

        scroll)
          grab_target "$@"
          dir="down"; amount="3"
          i=0
          while [ "$i" -lt "''${#REST[@]}" ]; do
            case "''${REST[$i]}" in
              --dir) i=$((i+1)); dir="''${REST[$i]:-}"; [ -n "$dir" ] || die "--dir needs a value" ;;
              --amount|-n) i=$((i+1)); amount="''${REST[$i]:-}"; [ -n "$amount" ] || die "--amount needs a value" ;;
              *) die "unknown scroll option: ''${REST[$i]}" ;;
            esac
            i=$((i+1))
          done
          req=$(jq -nc --arg d "$dir" --argjson n "$amount" '{verb:"scroll",dir:$d,amount:$n}')
          [ -n "$TARGET" ] && req=$(printf '%s' "$req" | jq -c --arg t "$TARGET" '. + {target:$t}')
          send "$req" ;;

        key)
          tgt=""; collected=0; chord_parts=()
          for a in "$@"; do
            if [ "$collected" -eq 1 ]; then chord_parts+=("$a")
            elif [ "$a" = "--" ]; then collected=1
            else case "$a" in -*) : ;; *) [ -z "$tgt" ] && tgt="$a" ;; esac
            fi
          done
          chord="''${chord_parts[*]:-}"
          [ -n "$chord" ] || die "usage: cua key [target] -- <keycode:state ...>"
          req=$(jq -nc --arg c "$chord" '{verb:"key",chord:$c}')
          [ -n "$tgt" ] && req=$(printf '%s' "$req" | jq -c --arg t "$tgt" '. + {target:$t}')
          send "$req" ;;

        target)
          sub="''${1:-list}"; shift || true
          case "$sub" in
            list)
              [ -s "$status" ] || die "no status file — is the cua daemon running?"
              jq -r '.targets[] | "\(.id)\t[\(.kind)]\t\(.output)\(if .sandbox then "\tsandbox" else "" end)"' "$status" ;;
            new)
              spawn=""
              while [ "$#" -gt 0 ]; do
                case "$1" in
                  --workspace) die "workspace targets are not implemented; use --headless" ;;
                  --headless) : ;;                       # the only (default) kind
                  --spawn) shift; spawn="''${1:-}" ;;
                esac
                shift || true
              done
              send "$(jq -nc --arg sp "$spawn" \
                      '{verb:"target_new"} + (if $sp!="" then {spawn:$sp} else {} end)')" ;;
            rm)
              [ "$#" -ge 1 ] || die "usage: cua target rm <id>"
              send "$(jq -nc --arg t "$1" '{verb:"target_rm",target:$t}')" ;;
            select)
              [ "$#" -ge 1 ] || die "usage: cua target select <id>"
              printf '%s' "$1" > "$deftarget"; echo "default target = $1" ;;
            *) die "unknown target subcommand '$sub'" ;;
          esac ;;

        panic) exec cua-panic ;;

        agent-mode|agentmode|agent)
          # Agent-mode lock (R17): stage the real desktop off-screen behind a
          # curtain so agents keep full CUA while the physical screen looks locked.
          sub="''${1:-status}"; shift || true
          case "$sub" in
            on|lock|start)    send "$(jq -nc '{verb:"agentmode",on:true}')" ;;
            off|unlock|stop)  send "$(jq -nc '{verb:"agentmode",on:false}')" ;;
            status)
              [ -s "$status" ] || die "no status file — is the cua daemon running?"
              jq -r 'if (.agentMode.active==true)
                     then "agent-mode: ON — desktop staged on \(.agentMode.stage) since \(.agentMode.since)"
                     else "agent-mode: off" end' "$status" ;;
            *) die "usage: cua agent-mode on|off|status" ;;
          esac ;;

        -h|--help|"")
          cat <<'EOF'
cua — computer-use-agent control for Hyprland (harness-agnostic)

PERCEPTION (no lease needed)
  cua see [TARGET] [--region "X,Y WxH"] [--out NAME] [--tree]
          (--out is a filename, written under $XDG_RUNTIME_DIR; click coords are
           PNG pixels — the reply's "scale" maps them to the pointer)

SEAT / CONTROL
  cua acquire <TARGET>          take the seat (sandbox: self-serve; real: needs grant)
  cua release                  release your lease
  cua grant <AGENT> [TARGET] [--lock]   USER mints push-to-grant for the real desktop
  cua revoke [AGENT]           USER revokes a grant / active lease now
  cua panic                    hard-stop all agent input, seat back to you

AGENT-MODE LOCK (USER)
  cua agent-mode on            lock the screen but keep agents driving your real
                               desktop (staged off-screen behind a curtain)
  cua agent-mode off           unlock — restore the desktop (Super+Shift+U)
  cua agent-mode status        is agent-mode active?

ACTION (must hold the lease)
  cua click  [TARGET] [--button left|right|middle] [--x N --y N]
  cua type   [TARGET] -- <text>
  cua scroll [TARGET] [--dir up|down] [--amount N]
  cua key    [TARGET] -- <keycode:state ...>

TARGETS
  cua target list
  cua target new [--headless] [--spawn CMD]
  cua target rm <ID>
  cua target select <ID>

STATUS
  cua status [--json|-j] [--watch|-w]

TARGET is 'real' (your desktop, default) or a 'sandbox-N' id from `target new`.
EOF
          ;;
        *) die "unknown command '$cmd' (try: cua --help)" ;;
      esac
    '';
  };
in
{
  home.packages = [ cli cua-panic cua-curtain cua-idle-lock pkgs.ydotool ];

  # ── ydotoold: the input-injection backend (user-level) ──────────────────────
  # User service (not programs.ydotool's root system service) to match the
  # agent-status user-session lifecycle and to make the panic primitive a clean
  # `systemctl --user kill`. Needs /dev/uinput, granted by modules/nixos/cua.nix.
  systemd.user.services.ydotoold = {
    Unit = {
      Description = "ydotoold (user) — input-injection backend for cua";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.ydotool}/bin/ydotoold --socket-path=%t/.ydotool_socket --socket-perm=0600";
      Restart = "always";
      RestartSec = 1;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # ── cua daemon: seat broker + target registry + status publisher ────────────
  systemd.user.services.cua = {
    Unit = {
      Description = "cua daemon — computer-use-agent seat broker for Hyprland";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" "ydotoold.service" ];
      Wants = [ "ydotoold.service" ];
    };
    Service = {
      Type = "simple";
      Environment = [ "PATH=${daemonPath}" ];
      ExecStart = "${daemon}";
      Restart = "on-failure";
      RestartSec = 2;
      # Light, non-critical broker — mirror agent-status' resource posture.
      Nice = 5;
      MemoryMax = "96M";
      OOMScoreAdjust = 300;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
