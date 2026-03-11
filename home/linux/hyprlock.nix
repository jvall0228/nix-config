{ lib, pkgs, config, ... }:
let
  # Hex-to-RGB converter for Stylix colors → hyprlock rgb() format
  hexToInt = c: {
    "0" = 0; "1" = 1; "2" = 2; "3" = 3; "4" = 4; "5" = 5; "6" = 6; "7" = 7;
    "8" = 8; "9" = 9; "a" = 10; "b" = 11; "c" = 12; "d" = 13; "e" = 14; "f" = 15;
  }.${c};
  hexPairToInt = s:
    (hexToInt (builtins.substring 0 1 s)) * 16 + (hexToInt (builtins.substring 1 1 s));
  hexToRgb = hex:
    "${toString (hexPairToInt (builtins.substring 0 2 hex))}, "
    + "${toString (hexPairToInt (builtins.substring 2 2 hex))}, "
    + "${toString (hexPairToInt (builtins.substring 4 2 hex))}";

  # Colors — derived from Stylix base16 where possible, literals for accent colors
  c = config.lib.stylix.colors;
  colors = {
    purple    = "#${c.base0E}";  # BB9AF7 — Claude label, header
    cyan      = "#${c.base0D}";  # 2AC3DE — cursor, typing indicator
    fg        = "#${c.base05}";  # A9B1D6 — main text
    fgBright  = "#${c.base08}";  # C0CAF5 — time display
    green     = "#${c.base0B}";  # 9ECE6A — "You:" label
    selection  = "#${c.base02}"; # 2F3549 — borders, separator
    bg        = c.base00;        # 1A1B26 — box backgrounds
    # Shimmer accent colors — no base16 equivalent, specific to JRPG aesthetic
    blue      = "#7AA2F7";
    comment   = "#565F89";
    lightCyan = "#7DCFFF";
    # Input field accents
    fail      = "#F7768E";
    capslock  = "#E0AF68";
    inputBg   = "rgba(30, 30, 46, 0.8)";
  };
  # Pre-computed rgb() strings for hyprlock config
  rgb = {
    bg80       = "rgba(${hexToRgb c.base00}, 0.80)";
    selection  = "rgb(${hexToRgb c.base02})";
    fg         = "rgb(${hexToRgb c.base05})";
    fgBright   = "rgb(${hexToRgb c.base08})";
    purple     = "rgb(${hexToRgb c.base0E})";
    green      = "rgb(${hexToRgb c.base0B})";
    blue       = "rgb(122, 162, 247)";  # #7AA2F7
    fail       = "rgb(247, 118, 142)";
    check      = "rgb(${hexToRgb c.base0B})";
    capslock   = "rgb(224, 175, 104)";
  };

  # Interface files (in $XDG_RUNTIME_DIR):
  #   clawd-jrpg-text    — word-wrapped dialogue lines (newline-separated)
  #   clawd-jrpg-user    — user's last message (single line, max 49 chars)
  #   clawd-jrpg-ts      — epoch nanoseconds when text last changed
  #   clawd-running      — pgrep cache (epoch seconds)
  #   clawd-line-{1,2,3} — rendered Pango markup for each display line
  #   hyprlock-weather   — cached weather string from wttr.in

  # Shared pgrep cache — checked at most every 2 seconds
  clawd-pgrep-check = pkgs.writeShellScript "clawd-pgrep-check" ''
    D="$XDG_RUNTIME_DIR"
    CACHE="$D/clawd-running"
    if [ -f "$CACHE" ]; then
      read -r CACHED_TS < "$CACHE"
      [ $(($EPOCHSECONDS - CACHED_TS)) -lt 2 ] && exit 0
    fi
    if pgrep -x claude >/dev/null 2>&1; then
      printf '%s' "$EPOCHSECONDS" > "$CACHE"
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
      [ $BLINK -eq 0 ] && CURSOR="<span foreground=\"${colors.cyan}\">█</span>" || CURSOR=" "
      echo "          <span foreground=\"${colors.purple}\">Claude</span>  <span foreground=\"${colors.selection}\">:</span>  <span foreground=\"${colors.cyan}\">''${VISIBLE}</span>''${CURSOR}          "
    else
      # Gradient shimmer: wave of color across verb characters
      COLORS=("${colors.comment}" "${colors.blue}" "${colors.cyan}" "${colors.lightCyan}" "${colors.cyan}" "${colors.blue}" "${colors.comment}")
      PHASE=$(( (NOW_NS / 120000000) % 21 ))
      SHIMMER=""
      FULL="''${VERB}..."
      FLEN=''${#FULL}
      for ((ch=0; ch<FLEN; ch++)); do
        color_idx=$(( (ch + PHASE) % 7 ))
        SHIMMER="''${SHIMMER}<span foreground=\"''${COLORS[$color_idx]}\">''${FULL:$ch:1}</span>"
      done
      echo "          <span foreground=\"${colors.purple}\">Claude</span>  <span foreground=\"${colors.selection}\">:</span>  ''${SHIMMER}          "
    fi
  '';

  # User message label script
  clawd-jrpg-user = pkgs.writeShellScript "clawd-jrpg-user" ''
    ${clawd-pgrep-check} || exit 0
    D="$XDG_RUNTIME_DIR"
    MSG=$(cat "$D/clawd-jrpg-user" 2>/dev/null)
    [ -z "$MSG" ] && exit 0
    # Escape pango markup
    MSG="''${MSG//&/&amp;}"
    MSG="''${MSG//</&lt;}"
    MSG="''${MSG//>/&gt;}"
    echo "          <span foreground=\"${colors.green}\">You:</span>  <span foreground=\"${colors.fg}\">''${MSG}</span>          "
  '';

  # Text script: typewriter effect from transcript
  clawd-jrpg-text = pkgs.writeShellScript "clawd-jrpg-text" ''
    # Line number from argument (1, 2, or 3)
    LINE=''${1:-1}
    [[ "$LINE" =~ ^[123]$ ]] || exit 1
    D="$XDG_RUNTIME_DIR"

    # Lines 2-3: just read cached output (near-instant)
    if [ "$LINE" -ne 1 ]; then
      cat "$D/clawd-line-''${LINE}" 2>/dev/null
      exit 0
    fi

    ${clawd-pgrep-check} || exit 0

    # Single date call for everything
    NOW_NS=$(date +%s%N)
    NOW_S=$((NOW_NS / 1000000000))

    # Cache transcript read (heavy — only every 2 seconds)
    CACHE_MTIME=$(stat -c %Y "$D/clawd-jrpg-text" 2>/dev/null || echo 0)
    if [ $((NOW_S - CACHE_MTIME)) -ge 2 ]; then
      SESSIONS_DIR="$HOME/.claude/projects"
      TRANSCRIPT=$(find "$SESSIONS_DIR" -maxdepth 2 -name "*.jsonl" -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | head -1 | cut -d' ' -f2-)
      if [ -n "$TRANSCRIPT" ]; then
        export TRANSCRIPT D
        MSG=$(${pkgs.python3}/bin/python3 << 'PYEOF'
import json, os, re, textwrap
transcript = os.environ.get("TRANSCRIPT", "")
if not transcript:
    exit()
d = os.environ.get("D", "/tmp")
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
            texts = []
            if isinstance(content, str):
                texts.append(content.strip())
            elif isinstance(content, list):
                for block in content:
                    if isinstance(block, dict) and block.get("type") == "text":
                        texts.append(block.get("text", "").strip())
                    elif isinstance(block, str):
                        texts.append(block.strip())
            for t in texts:
                if not t:
                    continue
                # Strip XML/system tags to get actual user text
                clean = re.sub(r"<[^>]+>", "", t).strip()
                # Skip skill expansions (start with #) and empty after strip
                if not clean or clean[0] == "#":
                    continue
                last_user = clean
        if data.get("type") == "assistant":
            for block in data.get("message", {}).get("content", []):
                if block.get("type") == "text":
                    t = block.get("text", "").strip()
                    if t:
                        # Strip XML/system tags from assistant text too
                        t = re.sub(r"<[^>]+>", "", t).strip()
                        if t:
                            last = t
# Write user message
user_path = os.path.join(d, "clawd-jrpg-user")
if last_user:
    u = last_user.replace("\n", " ").strip()
    if len(u) > 49:
        u = u[:46] + "..."
    old_u = ""
    try:
        with open(user_path, "r") as uf:
            old_u = uf.read().strip()
    except FileNotFoundError:
        pass
    if u != old_u:
        with open(user_path, "w") as uf:
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
          OLD=$(cat "$D/clawd-jrpg-text" 2>/dev/null)
          if [ "$MSG" != "$OLD" ]; then
            echo "$MSG" > "$D/clawd-jrpg-text"
            echo "$NOW_NS" > "$D/clawd-jrpg-ts"
          else
            touch "$D/clawd-jrpg-text"
          fi
        fi
      fi
    fi

    TS=$(cat "$D/clawd-jrpg-ts" 2>/dev/null)
    [ -z "$TS" ] && exit 0

    LINE_WIDTH=55
    TYPING_SPEED=30
    PAUSE_MS=5000
    MARGIN="          "

    # Read all word-wrapped lines from cache
    mapfile -t ALL_LINES < "$D/clawd-jrpg-text"
    TOTAL_LINES=''${#ALL_LINES[@]}
    if [ $TOTAL_LINES -eq 0 ]; then
      : > "$D/clawd-line-1"; : > "$D/clawd-line-2"; : > "$D/clawd-line-3"
      exit 0
    fi
    TOTAL_PAGES=$(( (TOTAL_LINES + 2) / 3 ))

    # Calculate timing
    ELAPSED_MS=$(( (NOW_NS - TS) / 1000000 ))

    # Find which page we're on
    TIME_CONSUMED=0 PAGE=0 PAGE_START_MS=0
    for ((pg=0; pg<TOTAL_PAGES; pg++)); do
      page_chars=0
      for ((line_idx=pg*3; line_idx<pg*3+3 && line_idx<TOTAL_LINES; line_idx++)); do
        page_chars=$((page_chars + ''${#ALL_LINES[$line_idx]}))
      done
      page_time=$((page_chars * TYPING_SPEED + PAUSE_MS))
      if [ $ELAPSED_MS -lt $((TIME_CONSUMED + page_time)) ] || [ $pg -eq $((TOTAL_PAGES - 1)) ]; then
        PAGE=$pg PAGE_START_MS=$TIME_CONSUMED; break
      fi
      TIME_CONSUMED=$((TIME_CONSUMED + page_time))
    done

    PAGE_LINE_START=$((PAGE * 3))
    HAS_MORE=0; [ $((PAGE + 1)) -lt $TOTAL_PAGES ] && HAS_MORE=1

    # Page char count
    PAGE_TOTAL_CHARS=0 PAGE_LINE_COUNT=0
    for ((idx=PAGE_LINE_START; idx<PAGE_LINE_START+3 && idx<TOTAL_LINES; idx++)); do
      PAGE_TOTAL_CHARS=$((PAGE_TOTAL_CHARS + ''${#ALL_LINES[$idx]})); PAGE_LINE_COUNT=$((PAGE_LINE_COUNT + 1))
    done

    # Typewriter progress
    PAGE_ELAPSED=$((ELAPSED_MS - PAGE_START_MS))
    [ $PAGE_ELAPSED -lt 0 ] && PAGE_ELAPSED=0
    TYPED_CHARS=$((PAGE_ELAPSED / TYPING_SPEED))
    [ $TYPED_CHARS -gt $PAGE_TOTAL_CHARS ] && TYPED_CHARS=$PAGE_TOTAL_CHARS
    BLINK=$(( (NOW_NS / 500000000) % 2 ))

    # Render all 3 lines
    CHAR_OFFSET=0
    for ((line=0; line<3; line++)); do
      LINE_INDEX=$((PAGE_LINE_START + line)) LINE_NUM=$((line + 1))
      if [ $LINE_INDEX -ge $TOTAL_LINES ]; then
        : > "$D/clawd-line-$LINE_NUM"
        [ $LINE_NUM -eq 1 ] && echo -n
        continue
      fi
      FULL_LINE="''${ALL_LINES[$LINE_INDEX]}" LINE_LEN=''${#FULL_LINE}

      if [ $TYPED_CHARS -le $CHAR_OFFSET ]; then
        : > "$D/clawd-line-$LINE_NUM"
        [ $LINE_NUM -eq 1 ] && echo -n
        CHAR_OFFSET=$((CHAR_OFFSET + LINE_LEN)); continue
      fi

      if [ $TYPED_CHARS -ge $((CHAR_OFFSET + LINE_LEN)) ]; then
        VISIBLE="$FULL_LINE" STILL_TYPING=0
      else
        VISIBLE="''${FULL_LINE:0:$((TYPED_CHARS - CHAR_OFFSET))}" STILL_TYPING=1
      fi

      IS_LAST_PAGE_LINE=0; [ $line -eq $((PAGE_LINE_COUNT - 1)) ] && IS_LAST_PAGE_LINE=1
      ELLIPSIS=""
      [ $IS_LAST_PAGE_LINE -eq 1 ] && [ $HAS_MORE -eq 1 ] && [ $STILL_TYPING -eq 0 ] && ELLIPSIS="..."

      ESCAPED="''${VISIBLE//&/&amp;}"; ESCAPED="''${ESCAPED//</&lt;}"; ESCAPED="''${ESCAPED//>/&gt;}"

      CURSOR_STR=""
      if [ $STILL_TYPING -eq 1 ]; then
        [ $BLINK -eq 0 ] && CURSOR_STR="<span foreground=\"${colors.cyan}\">█</span>" || CURSOR_STR=" "
      elif [ $IS_LAST_PAGE_LINE -eq 1 ] && [ $TYPED_CHARS -ge $PAGE_TOTAL_CHARS ]; then
        [ $BLINK -eq 0 ] && CURSOR_STR="<span foreground=\"${colors.cyan}\"> ▼</span>" || CURSOR_STR="  "
      fi

      VISIBLE_LEN=''${#VISIBLE} ELLIPSIS_LEN=''${#ELLIPSIS} CURSOR_LEN=0
      [ $STILL_TYPING -eq 1 ] && CURSOR_LEN=1 || { [ -n "$CURSOR_STR" ] && CURSOR_LEN=2; }
      PAD_LEN=$((LINE_WIDTH - VISIBLE_LEN - ELLIPSIS_LEN - CURSOR_LEN))
      [ $PAD_LEN -lt 0 ] && PAD_LEN=0
      PADDING=$(printf '%*s' "$PAD_LEN" "")

      OUTPUT="''${MARGIN}<span foreground=\"${colors.fg}\">''${ESCAPED}''${ELLIPSIS}</span>''${CURSOR_STR}''${PADDING}''${MARGIN}"
      printf '%s\n' "$OUTPUT" > "$D/clawd-line-$LINE_NUM"
      [ $LINE_NUM -eq 1 ] && printf '%s\n' "$OUTPUT"

      CHAR_OFFSET=$((CHAR_OFFSET + LINE_LEN))
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
        border_color = rgb.blue;
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
          color = rgb.bg80;
          rounding = 12;
          border_size = 2;
          border_color = rgb.selection;
          position = "0, -20";
          halign = "center";
          valign = "center";
          shadow_passes = 1;
        }
        {
          monitor = "";
          size = "900, 210";
          color = rgb.bg80;
          rounding = 12;
          border_size = 2;
          border_color = rgb.selection;
          position = "0, -150";
          halign = "center";
          valign = "center";
          shadow_passes = 1;
        }
        # Separator line inside box
        {
          monitor = "";
          size = "860, 1";
          color = rgb.selection;
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
          color = rgb.fgBright;
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
          color = rgb.fg;
          position = "0, -120";
          halign = "center";
          valign = "top";
          shadow_passes = 1;
        }
        # Weather
        {
          monitor = "";
          text = ''cmd[update:600000] cat "$XDG_RUNTIME_DIR/hyprlock-weather" 2>/dev/null'';
          font_size = 16;
          font_family = "JetBrainsMono Nerd Font";
          color = rgb.fg;
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
          color = rgb.fg;
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
          color = rgb.purple;
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
          color = rgb.fg;
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
          color = rgb.fg;
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
          color = rgb.fg;
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
        outer_color = rgb.blue;
        inner_color = colors.inputBg;
        font_color = rgb.fgBright;
        rounding = 15;
        dots_size = 0.33;
        dots_spacing = 0.15;
        dots_center = true;
        fade_on_empty = true;
        placeholder_text = ''<span foreground="##a9b1d6">Password...</span>'';
        font_family = "JetBrainsMono Nerd Font";
        fail_text = "Authentication failed";
        fail_color = rgb.fail;
        check_color = rgb.check;
        capslock_color = rgb.capslock;
        position = "0, 720";
        halign = "center";
        valign = "bottom";
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
