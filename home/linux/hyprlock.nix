{ lib, pkgs, ... }:
let
  # Shared pgrep cache — checked at most every 2 seconds
  clawd-pgrep-check = pkgs.writeShellScript "clawd-pgrep-check" ''
    CACHE=/tmp/clawd-running
    # Check cache age using bash builtin
    if [ -f "$CACHE" ]; then
      read -r CACHED_TS < "$CACHE"
      NOW=''${EPOCHSECONDS:-$(printf '%(%s)T' -1)}
      [ $((NOW - CACHED_TS)) -lt 2 ] && exit 0
    fi
    if pgrep -x claude >/dev/null 2>&1; then
      printf '%s' "''${EPOCHSECONDS:-$(printf '%(%s)T' -1)}" > "$CACHE"
      exit 0
    else
      rm -f "$CACHE"
      exit 1
    fi
  '';

  # Header script: "Claude : Verb..."
  clawd-jrpg-header = pkgs.writeShellScript "clawd-jrpg-header" ''
    ${clawd-pgrep-check} || exit 0

    VERBS=(
      Accomplishing Architecting Baking Bloviating Bootstrapping Brewing
      Calculating Caramelizing Cerebrating Channeling Clauding Cogitating
      Composing Computing Concocting Contemplating Crafting Crystallizing
      Deciphering Deliberating Enchanting Envisioning Fermenting Finagling
      Forging Formulating Frolicking Gallivanting Generating Hatching
      Hypothesizing Illuminating Imagining Incubating Innovating Manifesting
      Marinating Meandering Musing Navigating Noodling Orchestrating
      Percolating Philosophising Pondering Pontificating Processing Puzzling
      Ruminating Scheming Shimmering Simmering Spelunking Synthesizing
      Tinkering Transmuting Vibing Wandering Weaving Wrangling
    )
    # Single date call for both seconds and nanoseconds
    NOW_NS=$(date +%s%N)
    NOW_S=$((NOW_NS / 1000000000))
    SEED=$((NOW_S / 8))
    RANDOM=$SEED
    VERB="''${VERBS[$((RANDOM % ''${#VERBS[@]}))]}"

    # Typewriter: reveal verb characters based on time within 8s window
    WINDOW_START=$((SEED * 8))
    ELAPSED_MS=$(( (NOW_NS / 1000000) - (WINDOW_START * 1000) ))
    CHARS=$(( ELAPSED_MS / 30 ))
    VLEN=''${#VERB}
    [ $CHARS -gt $VLEN ] && CHARS=$VLEN
    VISIBLE="''${VERB:0:$CHARS}"

    if [ $CHARS -lt $VLEN ]; then
      BLINK=$(( (NOW_NS / 500000000) % 2 ))
      [ $BLINK -eq 0 ] && CURSOR="<span foreground=\"#2AC3DE\">█</span>" || CURSOR=" "
      echo "          <span foreground=\"#BB9AF7\">Claude</span>  <span foreground=\"#2F3549\">:</span>  <span foreground=\"#2AC3DE\">''${VISIBLE}</span>''${CURSOR}          "
    else
      # Gradient shimmer: wave of color across verb characters
      COLORS=("#565F89" "#7AA2F7" "#2AC3DE" "#7DCFFF" "#2AC3DE" "#7AA2F7" "#565F89")
      PHASE=$(( (NOW_NS / 120000000) % 21 ))
      SHIMMER=""
      FULL="''${VERB}..."
      FLEN=''${#FULL}
      for ((c=0; c<FLEN; c++)); do
        CI=$(( (c + PHASE) % 7 ))
        SHIMMER="''${SHIMMER}<span foreground=\"''${COLORS[$CI]}\">''${FULL:$c:1}</span>"
      done
      echo "          <span foreground=\"#BB9AF7\">Claude</span>  <span foreground=\"#2F3549\">:</span>  ''${SHIMMER}          "
    fi
  '';

  # User message label script
  clawd-jrpg-user = pkgs.writeShellScript "clawd-jrpg-user" ''
    ${clawd-pgrep-check} || exit 0
    MSG=$(cat /tmp/clawd-jrpg-user 2>/dev/null)
    [ -z "$MSG" ] && exit 0
    # Escape pango markup
    MSG="''${MSG//&/&amp;}"
    MSG="''${MSG//</&lt;}"
    MSG="''${MSG//>/&gt;}"
    echo "          <span foreground=\"#9ECE6A\">You:</span>  <span foreground=\"#A9B1D6\">''${MSG}</span>          "
  '';

  # Text script: typewriter effect from transcript
  clawd-jrpg-text = pkgs.writeShellScript "clawd-jrpg-text" ''
    # Line number from argument (1, 2, or 3)
    LINE=''${1:-1}

    # Lines 2-3: just read cached output (near-instant)
    if [ "$LINE" -ne 1 ]; then
      cat /tmp/clawd-line-''${LINE} 2>/dev/null
      exit 0
    fi

    ${clawd-pgrep-check} || exit 0

    # Single date call for everything
    NOW_NS=$(date +%s%N)
    NOW_S=$((NOW_NS / 1000000000))

    # Cache transcript read (heavy — only every 2 seconds)
    CACHE_MTIME=$(stat -c %Y /tmp/clawd-jrpg-text 2>/dev/null || echo 0)
    if [ $((NOW_S - CACHE_MTIME)) -ge 2 ]; then
      SESSIONS_DIR="$HOME/.claude/projects"
      TRANSCRIPT=$(find "$SESSIONS_DIR" -maxdepth 2 -name "*.jsonl" -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | head -1 | cut -d' ' -f2-)
      if [ -n "$TRANSCRIPT" ]; then
        export TRANSCRIPT
        MSG=$(${pkgs.python3}/bin/python3 << 'PYEOF'
import json, os, textwrap
transcript = os.environ.get("TRANSCRIPT", "")
if not transcript:
    exit()
last = None
last_user = None
with open(transcript) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        data = json.loads(line)
        if data.get("type") == "user":
            content = data.get("message", {}).get("content", [])
            if isinstance(content, str):
                t = content.strip()
                if t:
                    last_user = t
            elif isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "text":
                        t = block.get("text", "").strip()
                        if t:
                            last_user = t
                    elif isinstance(block, str):
                        t = block.strip()
                        if t:
                            last_user = t
        if data.get("type") == "assistant":
            for block in data.get("message", {}).get("content", []):
                if block.get("type") == "text":
                    t = block.get("text", "").strip()
                    if t:
                        last = t
# Write user message
if last_user:
    u = last_user.replace("\n", " ").strip()
    if len(u) > 49:
        u = u[:46] + "..."
    old_u = ""
    try:
        with open("/tmp/clawd-jrpg-user", "r") as uf:
            old_u = uf.read().strip()
    except FileNotFoundError:
        pass
    if u != old_u:
        with open("/tmp/clawd-jrpg-user", "w") as uf:
            uf.write(u)
if last:
    parts = []
    total = 0
    for l in last.split("\n"):
        l = l.strip()
        if not l or l[0] in "#|" or l.startswith("```") or (l[0] == "-" and not l.startswith("- **")):
            continue
        if l.startswith("- **"):
            l = l.lstrip("- ").replace("**", "")
        parts.append(l)
        total += len(l) + 1
        if total >= 600:
            break
    if parts:
        text = " ".join(parts)
        lines = textwrap.wrap(text, width=55, break_long_words=True, break_on_hyphens=True)
        if lines:
            print("\n".join(lines))
PYEOF
        )
        if [ -n "$MSG" ]; then
          OLD=$(cat /tmp/clawd-jrpg-text 2>/dev/null)
          if [ "$MSG" != "$OLD" ]; then
            echo "$MSG" > /tmp/clawd-jrpg-text
            echo "$NOW_NS" > /tmp/clawd-jrpg-ts
          else
            touch /tmp/clawd-jrpg-text
          fi
        fi
      fi
    fi

    TS=$(cat /tmp/clawd-jrpg-ts 2>/dev/null)
    [ -z "$TS" ] && exit 0

    LINE_WIDTH=55
    TYPING_SPEED=30
    PAUSE_MS=5000
    M="          "

    # Read all word-wrapped lines from cache
    mapfile -t AL < /tmp/clawd-jrpg-text
    TL=''${#AL[@]}
    if [ $TL -eq 0 ]; then
      : > /tmp/clawd-line-1; : > /tmp/clawd-line-2; : > /tmp/clawd-line-3
      exit 0
    fi
    TP=$(( (TL + 2) / 3 ))

    # Calculate timing
    ELAPSED_MS=$(( (NOW_NS - TS) / 1000000 ))

    # Find which page we're on
    TC=0 PG=0 PS_MS=0
    for ((p=0; p<TP; p++)); do
      PC=0
      for ((j=p*3; j<p*3+3 && j<TL; j++)); do
        PC=$((PC + ''${#AL[$j]}))
      done
      PT=$((PC * TYPING_SPEED + PAUSE_MS))
      if [ $ELAPSED_MS -lt $((TC + PT)) ] || [ $p -eq $((TP - 1)) ]; then
        PG=$p PS_MS=$TC; break
      fi
      TC=$((TC + PT))
    done

    PLS=$((PG * 3))
    HM=0; [ $((PG + 1)) -lt $TP ] && HM=1

    # Page char count
    PTC=0 PLC=0
    for ((i=PLS; i<PLS+3 && i<TL; i++)); do
      PTC=$((PTC + ''${#AL[$i]})); PLC=$((PLC + 1))
    done

    # Typewriter progress
    PE=$((ELAPSED_MS - PS_MS))
    [ $PE -lt 0 ] && PE=0
    TY=$((PE / TYPING_SPEED))
    [ $TY -gt $PTC ] && TY=$PTC
    BL=$(( (NOW_NS / 500000000) % 2 ))

    # Render all 3 lines
    CO=0
    for ((L=0; L<3; L++)); do
      LI=$((PLS + L)) LN=$((L + 1))
      if [ $LI -ge $TL ]; then
        : > /tmp/clawd-line-$LN
        [ $LN -eq 1 ] && echo -n
        continue
      fi
      FL="''${AL[$LI]}" LL=''${#FL}

      if [ $TY -le $CO ]; then
        : > /tmp/clawd-line-$LN
        [ $LN -eq 1 ] && echo -n
        CO=$((CO + LL)); continue
      fi

      if [ $TY -ge $((CO + LL)) ]; then
        V="$FL" SC=0
      else
        V="''${FL:0:$((TY - CO))}" SC=1
      fi

      ILP=0; [ $L -eq $((PLC - 1)) ] && ILP=1
      EL=""
      [ $ILP -eq 1 ] && [ $HM -eq 1 ] && [ $SC -eq 0 ] && EL="..."

      E="''${V//&/&amp;}"; E="''${E//</&lt;}"; E="''${E//>/&gt;}"

      C=""
      if [ $SC -eq 1 ]; then
        [ $BL -eq 0 ] && C="<span foreground=\"#2AC3DE\">█</span>" || C=" "
      elif [ $ILP -eq 1 ] && [ $TY -ge $PTC ]; then
        [ $BL -eq 0 ] && C="<span foreground=\"#2AC3DE\"> ▼</span>" || C="  "
      fi

      VL=''${#V} ELL=''${#EL} CL=0
      [ $SC -eq 1 ] && CL=1 || { [ -n "$C" ] && CL=2; }
      PL=$((LINE_WIDTH - VL - ELL - CL))
      [ $PL -lt 0 ] && PL=0
      P=$(printf '%*s' "$PL" "")

      O="''${M}<span foreground=\"#A9B1D6\">''${E}''${EL}</span>''${C}''${P}''${M}"
      printf '%s\n' "$O" > /tmp/clawd-line-$LN
      [ $LN -eq 1 ] && printf '%s\n' "$O"

      CO=$((CO + LL))
    done
  '';
in
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
        size = 300;
        rounding = -1;
        border_size = 5;
        border_color = "rgb(122, 162, 247)";
        position = "0, -720";
        halign = "center";
        valign = "top";
        shadow_passes = 1;
      }];

      # JRPG text box (always visible — subtle when empty)
      shape = [
        # User message box (above JRPG box)
        {
          monitor = "";
          size = "900, 40";
          color = "rgba(26, 27, 38, 0.80)";
          rounding = 12;
          border_size = 2;
          border_color = "rgb(47, 53, 73)";
          position = "0, -20";
          halign = "center";
          valign = "center";
          shadow_passes = 1;
        }
        {
          monitor = "";
          size = "900, 210";
          color = "rgba(26, 27, 38, 0.80)";
          rounding = 12;
          border_size = 2;
          border_color = "rgb(47, 53, 73)";
          position = "0, -150";
          halign = "center";
          valign = "center";
          shadow_passes = 1;
        }
        # Separator line inside box
        {
          monitor = "";
          size = "860, 1";
          color = "rgb(47, 53, 73)";
          rounding = 0;
          border_size = 0;
          position = "0, -115";
          halign = "center";
          valign = "center";
        }
      ];

      label = [
        # Time (top)
        {
          monitor = "";
          text = "$TIME";
          font_size = 64;
          font_family = "JetBrainsMono Nerd Font";
          color = "rgb(192, 202, 245)";
          position = "0, -40";
          halign = "center";
          valign = "top";
          shadow_passes = 1;
        }
        # Date
        {
          monitor = "";
          text = ''cmd[update:43200000] date +"%A, %B %d"'';
          font_size = 20;
          font_family = "JetBrainsMono Nerd Font";
          color = "rgb(169, 177, 214)";
          position = "0, -120";
          halign = "center";
          valign = "top";
          shadow_passes = 1;
        }
        # Weather
        {
          monitor = "";
          text = ''cmd[update:600000] cat /tmp/hyprlock-weather 2>/dev/null'';
          font_size = 16;
          font_family = "JetBrainsMono Nerd Font";
          color = "rgb(169, 177, 214)";
          position = "0, -155";
          halign = "center";
          valign = "top";
          shadow_passes = 1;
        }
        # User message label (inside user box)
        {
          monitor = "";
          text = ''cmd[update:2000] ${clawd-jrpg-user}'';
          font_size = 18;
          font_family = "JetBrainsMono Nerd Font";
          color = "rgb(169, 177, 214)";
          position = "0, -20";
          halign = "center";
          valign = "center";
          shadow_passes = 0;
        }
        # JRPG header (inside box, top)
        {
          monitor = "";
          text = ''cmd[update:30] ${clawd-jrpg-header}'';
          font_size = 18;
          font_family = "JetBrainsMono Nerd Font";
          color = "rgb(187, 154, 247)";
          position = "0, -90";
          halign = "center";
          valign = "center";
          shadow_passes = 0;
        }
        # JRPG typewriter text line 1
        {
          monitor = "";
          text = ''cmd[update:30] ${clawd-jrpg-text} 1'';
          font_size = 16;
          font_family = "JetBrainsMono Nerd Font";
          color = "rgb(169, 177, 214)";
          position = "0, -145";
          halign = "center";
          valign = "center";
          shadow_passes = 0;
        }
        # JRPG typewriter text line 2
        {
          monitor = "";
          text = ''cmd[update:30] ${clawd-jrpg-text} 2'';
          font_size = 16;
          font_family = "JetBrainsMono Nerd Font";
          color = "rgb(169, 177, 214)";
          position = "0, -173";
          halign = "center";
          valign = "center";
          shadow_passes = 0;
        }
        # JRPG typewriter text line 3
        {
          monitor = "";
          text = ''cmd[update:30] ${clawd-jrpg-text} 3'';
          font_size = 16;
          font_family = "JetBrainsMono Nerd Font";
          color = "rgb(169, 177, 214)";
          position = "0, -201";
          halign = "center";
          valign = "center";
          shadow_passes = 0;
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
        position = "0, 720";
        halign = "center";
        valign = "bottom";
        shadow_passes = 1;
      }];
    };
  };

  systemd.user.services.weather-cache = {
    Unit.Description = "Cache weather data for hyprlock";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.writeShellScript "weather-fetch" ''
        curl -s --max-time 10 "wttr.in/?format=%c+%t" > /tmp/hyprlock-weather 2>/dev/null
      ''}";
      ExecStopPost = "${pkgs.coreutils}/bin/rm -f /tmp/hyprlock-weather";
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
