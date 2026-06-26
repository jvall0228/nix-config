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

  # JRPG box chrome, pre-rendered to PNGs so the box can be HIDDEN when idle.
  # hyprlock `shape`s are static (always drawn, so an empty bordered box lingers when
  # no agent runs); an `image`, by contrast, can swap its source via reload_cmd. We
  # render at 2x (1800x420 / 1800x80) for crispness on this HiDPI panel — the image
  # widget's `size` scales each back to the 900x210 / 900x40 logical footprint the old
  # shapes used (size = the logical HEIGHT, since hyprlock keeps aspect ratio). Colours
  # come straight from Stylix (translucent base00 fill, base02 border + separator).
  boxAssets = pkgs.runCommand "clawd-jrpg-boxes"
    { nativeBuildInputs = [ pkgs.imagemagick ]; } ''
    mkdir -p "$out"
    # Main dialogue box: rounded rect (r=24 = the old rounding 12 at 2x), 4px border,
    # with the inner separator baked in at y=140 (70 logical px below the top edge).
    magick -size 1800x420 xc:none \
      -fill '${rgb.bg80}' -stroke '${colors.selection}' -strokewidth 4 \
      -draw 'roundrectangle 2,2 1797,417 24,24' \
      -stroke '${colors.selection}' -strokewidth 2 \
      -draw 'line 40,140 1760,140' \
      "$out/mainbox.png"
    # User-message box (sits above the main box).
    magick -size 1800x80 xc:none \
      -fill '${rgb.bg80}' -stroke '${colors.selection}' -strokewidth 4 \
      -draw 'roundrectangle 2,2 1797,77 24,24' \
      "$out/userbox.png"
    # Fully-transparent source shown when no agent is running (box hidden). reload_cmd
    # must always echo a path — an empty echo would keep the previous image — so the
    # idle state points here instead of emitting nothing.
    magick -size 8x8 xc:none "$out/transparent.png"
  '';

  # Interface files (in $XDG_RUNTIME_DIR):
  #   clawd-jrpg-text     — word-wrapped dialogue lines (newline-separated)
  #   clawd-jrpg-user     — current session's user message (single line, max 49 chars)
  #   clawd-jrpg-head     — current session meta for the header: agent\tdir\ttotal\tidx
  #   clawd-jrpg-ts       — epoch nanoseconds when text last changed
  #   clawd-session-cursor— which session is shown (index; set by the cycle keybind)
  #   clawd-running       — pgrep cache (epoch seconds)
  #   clawd-line-{1,2,3}  — rendered Pango markup for each display line
  #   hyprlock-weather    — cached weather string from wttr.in
  #
  # clawd-jrpg-text (line 1) is the single daemon reader: ~1x/s it picks the session
  # at clawd-session-cursor from agent-status.json's .hyprlock.sessions[] and refreshes
  # the text/user/head caches. The header & user labels just `cat` those caches, so the
  # 30ms render path stays fork-free. The cycle keybind bumps the cursor and forces an
  # immediate re-read (see clawd-session-cycle in hyprland.nix).

  # Shared pgrep cache — checked at most every 2 seconds
  clawd-pgrep-check = pkgs.writeShellScript "clawd-pgrep-check" ''
    D="$XDG_RUNTIME_DIR"
    CACHE="$D/clawd-running"
    if [ -f "$CACHE" ]; then
      read -r CACHED_TS < "$CACHE"
      [ $(($EPOCHSECONDS - CACHED_TS)) -lt 2 ] && exit 0
    fi
    # Prefer the agent-status daemon's published state; fall back to a direct
    # pgrep if its file is missing or stale (>5s) so the lock screen still works
    # when the daemon is down. Gate on `.any` so the box shows for ANY running
    # agent (claude/codex/gemini/opencode), not just claude. (NixOS wraps the
    # binaries, so the comms are ".claude-wrapped", ".codex-wrapped",
    # ".opencode-wrapp" (15-char truncation); gemini is a node process running
    # gemini.js — match all of them in the fallback.)
    STATUS="$D/agent-status.json"
    MT=$(stat -c %Y "$STATUS" 2>/dev/null || echo 0)
    if [ $(($EPOCHSECONDS - MT)) -le 5 ]; then
      if ${pkgs.jq}/bin/jq -e '.any == true' "$STATUS" >/dev/null 2>&1; then
        printf '%s' "$EPOCHSECONDS" > "$CACHE"; exit 0
      else
        rm -f "$CACHE" "$D/clawd-session-cursor"; exit 1
      fi
    fi
    if pgrep -x .claude-wrapped >/dev/null 2>&1 \
       || pgrep -x .codex-wrapped >/dev/null 2>&1 \
       || pgrep -x .opencode-wrapp >/dev/null 2>&1 \
       || pgrep -x claude >/dev/null 2>&1 \
       || pgrep -f 'gemini\.js' >/dev/null 2>&1; then
      printf '%s' "$EPOCHSECONDS" > "$CACHE"
      exit 0
    else
      # Idle: drop the caches AND reset the session cursor so the next lock starts
      # at the speaker (session 0) instead of a stale index.
      rm -f "$CACHE" "$D/clawd-session-cursor"
      exit 1
    fi
  '';

  # Header script: "<Speaker> : Verb..."  (+ working dir and [n/total] when cycling)
  clawd-jrpg-header = pkgs.writeShellScript "clawd-jrpg-header" ''
    ${clawd-pgrep-check} || exit 0

    # Current session's agent + dir + position come from the head cache that
    # clawd-jrpg-text refreshes (cheap cat; no jq on this 30ms render path). When more
    # than one session is running, show "<Agent>  <dir>  [idx/total]" so each cycled
    # session is identifiable; a single session stays just "<Agent>".
    D="$XDG_RUNTIME_DIR"
    SPEAKER="Claude"; SUBTITLE=""
    # cat (not a `< file` redirect) so a momentarily-missing cache — e.g. the first
    # frame after lock, before clawd-jrpg-text has run once — doesn't leak a redirect
    # error; the herestring then parses whatever's there (empty → defaults below).
    HAGENT=""; HDIR=""; HTOTAL=0; HIDX=0
    IFS=$'\t' read -r HAGENT HDIR HTOTAL HIDX <<< "$(cat "$D/clawd-jrpg-head" 2>/dev/null)"
    [ -n "$HAGENT" ] && SPEAKER="$HAGENT"
    if [ "''${HTOTAL:-0}" -gt 1 ] 2>/dev/null; then
      POS="$((HIDX + 1))/$HTOTAL"
      DIRSPAN=""
      [ -n "$HDIR" ] && DIRSPAN="<span foreground=\"${colors.green}\">''${HDIR}</span>  "
      SUBTITLE="''${DIRSPAN}<span foreground=\"${colors.comment}\">[''${POS}]</span>  "
    fi

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
      echo "          <span foreground=\"${colors.purple}\">''${SPEAKER}</span>  ''${SUBTITLE}<span foreground=\"${colors.selection}\">:</span>  <span foreground=\"${colors.cyan}\">''${VISIBLE}</span>''${CURSOR}          "
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
      echo "          <span foreground=\"${colors.purple}\">''${SPEAKER}</span>  ''${SUBTITLE}<span foreground=\"${colors.selection}\">:</span>  ''${SHIMMER}          "
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

    # Pull the parsed transcript content from the agent-status daemon, which owns
    # the heavy pgrep + transcript parse and publishes agent-status.json. We only
    # read it ~once/second (the `touch` keeps this rate-limit working); the 30ms
    # render below stays a cheap cat of the flat cache files. The ts-reset-on-
    # content-change rule is the load-bearing typewriter clock and stays HERE in
    # the consumer, so the animation restarts from char 0 only when (and as soon
    # as) the displayed text actually changes — exactly as before, lock or not.
    CACHE_MTIME=$(stat -c %Y "$D/clawd-jrpg-text" 2>/dev/null || echo 0)
    if [ $((NOW_S - CACHE_MTIME)) -ge 1 ]; then
      STATUS="$D/agent-status.json"
      # Which session to display: the cursor (set by the cycle keybind) wrapped into
      # the running-session count. .hyprlock.sessions[] is most-recently-active first,
      # so index 0 is the speaker. One jq pass yields idx/total/agent/dir (all non-empty
      # so the tab-split can't collapse fields); the agent/assistant text follow.
      CUR=$(cat "$D/clawd-session-cursor" 2>/dev/null); [ -z "$CUR" ] && CUR=0
      case "$CUR" in *[!0-9-]*) CUR=0 ;; esac
      META=$(${pkgs.jq}/bin/jq -r --argjson c "$CUR" '
        (.hyprlock.sessions // []) as $s | ($s|length) as $n
        | if $n == 0 then "0\t0\tClaude\tClaude"
          else (($c % $n + $n) % $n) as $i
            | "\($i)\t\($n)\t\($s[$i].agent // "Claude")\t\($s[$i].dir // "Claude")" end
      ' "$STATUS" 2>/dev/null)
      IFS=$'\t' read -r IDX TOTAL HAGENT HDIR <<< "$META"
      [ -z "$IDX" ] && IDX=0; case "$IDX" in *[!0-9]*) IDX=0 ;; esac
      # Head cache the header cats (agent \t dir \t total \t idx); trailing newline so
      # the header's `read` gets a clean line.
      printf '%s\t%s\t%s\t%s\n' "''${HAGENT:-Claude}" "''${HDIR:-Claude}" "''${TOTAL:-0}" "$IDX" > "$D/clawd-jrpg-head"
      MSG=$(${pkgs.jq}/bin/jq -r --argjson i "$IDX" '.hyprlock.sessions[$i].lines // [] | join("\n")' "$STATUS" 2>/dev/null)
      USR=$(${pkgs.jq}/bin/jq -r --argjson i "$IDX" '.hyprlock.sessions[$i].user // empty' "$STATUS" 2>/dev/null)
      if [ -n "$USR" ]; then
        OLD_U=$(cat "$D/clawd-jrpg-user" 2>/dev/null)
        [ "$USR" != "$OLD_U" ] && printf '%s' "$USR" > "$D/clawd-jrpg-user"
      else
        : > "$D/clawd-jrpg-user"  # this session has no user line — clear any stale one
      fi
      if [ -n "$MSG" ]; then
        OLD=$(cat "$D/clawd-jrpg-text" 2>/dev/null)
        if [ "$MSG" != "$OLD" ]; then
          printf '%s\n' "$MSG" > "$D/clawd-jrpg-text"
          printf '%s' "$NOW_NS" > "$D/clawd-jrpg-ts"
        else
          touch "$D/clawd-jrpg-text"
        fi
      else
        # No displayable text this tick — still refresh the mtime so the ~1s
        # rate-limit holds (otherwise line-1 re-runs jq every 30ms). Empty file
        # renders blank; ts stays unset so the typewriter shows nothing.
        touch "$D/clawd-jrpg-text" 2>/dev/null
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

      image = [
        # Avatar (animated clawd frames whenever ANY agent runs, static otherwise).
        {
          monitor = "";
          path = "~/nix-config/assets/avatar.png";
          reload_cmd = "${clawd-pgrep-check} && echo ~/nix-config/assets/clawd-frame-$(($(date +%s) % 4)).png || echo ~/nix-config/assets/avatar.png";
          reload_time = 1;
          size = 300;
          rounding = -1;
          border_size = 5;
          border_color = rgb.blue;
          position = "0, -720";
          halign = "center";
          valign = "top";
          shadow_passes = 1;
        }
        # JRPG boxes as images (NOT shapes) so they HIDE when no agent is running:
        # reload_cmd swaps to a transparent PNG while idle. They render in the image
        # category, which draws under the label category — so the dialogue text still
        # sits on top. `size` = logical height; width follows by aspect (900x40 /
        # 900x210), matching the old shapes' footprint and position exactly.
        {
          monitor = "";
          path = "${boxAssets}/transparent.png";
          reload_cmd = "${clawd-pgrep-check} && echo ${boxAssets}/userbox.png || echo ${boxAssets}/transparent.png";
          reload_time = 1;
          size = 40;
          rounding = 0;
          border_size = 0;
          position = "0, -20";
          halign = "center";
          valign = "center";
          shadow_passes = 0;
        }
        {
          monitor = "";
          path = "${boxAssets}/transparent.png";
          reload_cmd = "${clawd-pgrep-check} && echo ${boxAssets}/mainbox.png || echo ${boxAssets}/transparent.png";
          reload_time = 1;
          size = 210;
          rounding = 0;
          border_size = 0;
          position = "0, -150";
          halign = "center";
          valign = "center";
          shadow_passes = 0;
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
          text = ''cmd[update:200] ${clawd-jrpg-user}'';
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
