{ pkgs, ... }:
let
  wallpaper-set = pkgs.writeShellScriptBin "wallpaper-set" ''
    set -euo pipefail

    STATE_DIR="$HOME/.local/state/wallpaper"
    mkdir -p "$STATE_DIR"

    # PID files
    SWWW_PID_FILE="$STATE_DIR/swww-daemon.pid"
    SLIDESHOW_PID_FILE="$STATE_DIR/slideshow.pid"
    MPVPAPER_PID_FILE="$STATE_DIR/mpvpaper.pid"
    MPVPAPER_RESTARTER_PID_FILE="$STATE_DIR/mpvpaper-restarter.pid"

    # State files
    MODE_FILE="$STATE_DIR/mode"
    CURRENT_FILE="$STATE_DIR/current-file"
    LAST_ANIMATED_FILE="$STATE_DIR/last-animated-mode"
    BATTERY_OVERRIDE_FILE="$STATE_DIR/battery-override"

    usage() {
        cat <<'USAGE'
    Usage: wallpaper-set <mode> [file]

    Modes:
      static <file>       Set a static wallpaper (jpg, png, webp)
      gif <file>          Set an animated GIF/APNG wallpaper
      video <file>        Set a video wallpaper via mpvpaper
      slideshow           Cycle through ~/Pictures/Wallpapers every 5 minutes
    USAGE
        exit 1
    }

    pid_alive() {
        local pid_file="$1"
        if [ -f "$pid_file" ]; then
            local pid
            pid="$(cat "$pid_file")"
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                return 0
            fi
        fi
        return 1
    }

    kill_pid_file() {
        local pid_file="$1"
        if [ -f "$pid_file" ]; then
            local pid
            pid="$(cat "$pid_file")"
            if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
                wait "$pid" 2>/dev/null || true
            fi
            rm -f "$pid_file"
        fi
    }

    kill_mpvpaper() {
        kill_pid_file "$MPVPAPER_RESTARTER_PID_FILE"
        kill_pid_file "$MPVPAPER_PID_FILE"
    }

    kill_slideshow() {
        kill_pid_file "$SLIDESHOW_PID_FILE"
    }

    kill_swww() {
        kill_pid_file "$SWWW_PID_FILE"
    }

    ensure_swww() {
        if pid_alive "$SWWW_PID_FILE" && swww query 2>/dev/null 1>/dev/null; then
            return
        fi
        rm -f "$SWWW_PID_FILE"
        swww-daemon &
        echo $! > "$SWWW_PID_FILE"
        local attempts=0
        while ! swww query 2>/dev/null; do
            sleep 0.1
            attempts=$((attempts + 1))
            if [ "$attempts" -ge 50 ]; then
                echo "error: swww-daemon failed to start after 5 seconds" >&2
                exit 1
            fi
        done
    }

    start_mpvpaper_restarter() {
        local video_file="$1"
        local monitor
        monitor="$(hyprctl monitors -j | jq -r '.[0].name')"

        if [ -z "$monitor" ] || [ "$monitor" = "null" ]; then
            echo "error: could not detect monitor from hyprctl" >&2
            exit 1
        fi

        (
            while true; do
                mpvpaper -s -o "no-audio loop hwdec=auto gpu-api=vulkan" "$monitor" "$video_file" &
                MPVPAPER_PID=$!
                echo "$MPVPAPER_PID" > "$MPVPAPER_PID_FILE"
                sleep 1800
                kill "$MPVPAPER_PID" 2>/dev/null || true
                wait "$MPVPAPER_PID" 2>/dev/null || true
                sleep 1
            done
        ) &
        echo $! > "$MPVPAPER_RESTARTER_PID_FILE"
        disown
    }

    start_slideshow() {
        (
            export SWWW_TRANSITION_FPS=60
            export SWWW_TRANSITION_STEP=2
            while true; do
                find ~/Pictures/Wallpapers -type f \( -name '*.jpg' -o -name '*.png' -o -name '*.webp' \) |
                sort -R |
                while read -r img; do
                    swww img "$img" --transition-type random --transition-duration 2
                    sleep 300
                done
            done
        ) &
        echo $! > "$SLIDESHOW_PID_FILE"
        disown
    }

    write_state() {
        local mode="$1"
        local file="''${2:-}"

        echo "$mode" > "$MODE_FILE"
        echo "$file" > "$CURRENT_FILE"

        if [ "$mode" != "static" ]; then
            echo "$mode $file" > "$LAST_ANIMATED_FILE"
            touch "$BATTERY_OVERRIDE_FILE"
        else
            rm -f "$BATTERY_OVERRIDE_FILE"
        fi
    }

    validate_file() {
        local file="$1"
        if [ ! -f "$file" ]; then
            echo "error: file not found: $file" >&2
            exit 1
        fi
    }

    # --- Main ---

    if [ $# -lt 1 ]; then
        usage
    fi

    MODE="$1"
    FILE="''${2:-}"

    case "$MODE" in
        static)
            [ -z "$FILE" ] && { echo "error: static mode requires a file argument" >&2; usage; }
            validate_file "$FILE"
            FILE="$(realpath "$FILE")"

            kill_slideshow
            kill_mpvpaper
            ensure_swww

            swww img "$FILE" \
                --transition-type fade \
                --transition-duration 2 \
                --transition-fps 60

            write_state "static" "$FILE"
            ;;

        gif)
            [ -z "$FILE" ] && { echo "error: gif mode requires a file argument" >&2; usage; }
            validate_file "$FILE"
            FILE="$(realpath "$FILE")"

            kill_slideshow
            kill_mpvpaper
            ensure_swww

            swww img "$FILE" \
                --transition-type fade \
                --transition-duration 2 \
                --transition-fps 60

            write_state "gif" "$FILE"
            ;;

        video)
            [ -z "$FILE" ] && { echo "error: video mode requires a file argument" >&2; usage; }
            validate_file "$FILE"
            FILE="$(realpath "$FILE")"

            kill_slideshow
            kill_mpvpaper
            kill_swww

            start_mpvpaper_restarter "$FILE"

            write_state "video" "$FILE"
            ;;

        slideshow)
            kill_slideshow
            kill_mpvpaper
            ensure_swww

            start_slideshow

            write_state "slideshow" ""
            ;;

        *)
            echo "error: unknown mode '$MODE'" >&2
            usage
            ;;
    esac
  '';

  wallpaper-menu = pkgs.writeShellScriptBin "wallpaper-menu" ''
    STATIC_DIR="$HOME/Pictures/Wallpapers"
    VIDEO_DIR="$HOME/Videos/Wallpapers"

    show_root() {
        printf '\0prompt\x1fWallpaper\n'
        printf '\0data\x1froot\n'
        printf 'Static\0icon\x1fimage-x-generic\x1finfo\x1fmode:static\n'
        printf 'GIF/APNG\0icon\x1fimage-gif\x1finfo\x1fmode:gif\n'
        printf 'Slideshow\0icon\x1fmedia-playlist\x1finfo\x1fmode:slideshow\n'
        printf 'Video\0icon\x1fvideo-x-generic\x1finfo\x1fmode:video\n'
    }

    show_files() {
        local mode="$1"
        local label

        case "$mode" in
            static)
                label="Static"
                mapfile -t files < <(find "$STATIC_DIR" -type f \( -name '*.jpg' -o -name '*.png' -o -name '*.webp' \) 2>/dev/null | sort)
                ;;
            gif)
                label="GIF/APNG"
                mapfile -t files < <(find "$STATIC_DIR" -type f \( -name '*.gif' -o -name '*.apng' \) 2>/dev/null | sort)
                ;;
            video)
                label="Video"
                mapfile -t files < <(find "$VIDEO_DIR" -type f \( -name '*.mp4' -o -name '*.mkv' -o -name '*.webm' -o -name '*.mov' \) 2>/dev/null | sort)
                ;;
        esac

        printf '\0prompt\x1f%s\n' "$label"
        printf '\0data\x1fmode:%s\n' "$mode"
        printf '.. Back\0icon\x1fgo-previous\x1finfo\x1f__back__\n'

        if [ ''${#files[@]} -eq 0 ]; then
            printf '(no files found)\0nonselectable\x1ftrue\n'
            return
        fi

        for f in "''${files[@]}"; do
            local name
            name="$(basename "$f")"
            printf '%s\0icon\x1f%s\x1finfo\x1ffile:%s\n' "$name" "$f" "$f"
        done
    }

    # Initial call
    if [ "''${ROFI_RETV:-0}" -eq 0 ]; then
        if [ -z "''${ROFI_DATA:-}" ] || [ "''${ROFI_DATA:-}" = "root" ]; then
            show_root
        elif [[ "''${ROFI_DATA:-}" == mode:* ]]; then
            show_files "''${ROFI_DATA#mode:}"
        fi
        exit 0
    fi

    # User selected an entry
    if [ "''${ROFI_RETV:-0}" -eq 1 ]; then
        info="''${ROFI_INFO:-}"

        # Back to root
        if [ "$info" = "__back__" ]; then
            show_root
            exit 0
        fi

        # Root menu mode selected
        if [[ "$info" == mode:* ]]; then
            local_mode="''${info#mode:}"

            # Slideshow fires immediately
            if [ "$local_mode" = "slideshow" ]; then
                wallpaper-set slideshow >/dev/null 2>&1 &
                disown
                exit 0
            fi

            show_files "$local_mode"
            exit 0
        fi

        # File selected
        if [[ "$info" == file:* ]]; then
            filepath="''${info#file:}"
            mode="''${ROFI_DATA#mode:}"
            wallpaper-set "$mode" "$filepath" >/dev/null 2>&1 &
            disown
            exit 0
        fi
    fi
  '';

  wallpaper-init = pkgs.writeShellScriptBin "wallpaper-init" ''
    set -euo pipefail

    STATE_DIR="$HOME/.local/state/wallpaper"

    mkdir -p "$STATE_DIR"
    mkdir -p ~/Pictures/Wallpapers
    mkdir -p ~/Videos/Wallpapers

    # Start swww-daemon
    swww-daemon &
    echo $! > "$STATE_DIR/swww-daemon.pid"

    # Poll until ready
    while ! swww query 2>/dev/null; do
        sleep 0.1
    done

    # Restore last state or apply default
    if [ -f "$STATE_DIR/mode" ]; then
        MODE=$(cat "$STATE_DIR/mode")
        FILE=$(cat "$STATE_DIR/current-file" 2>/dev/null || echo "")
        wallpaper-set "$MODE" "$FILE"
    else
        swww img ~/nix-config/assets/wallpaper.png \
            --transition-type fade \
            --transition-duration 2 \
            --transition-fps 60
        echo "static" > "$STATE_DIR/mode"
        echo "$HOME/nix-config/assets/wallpaper.png" > "$STATE_DIR/current-file"
    fi
  '';

  wallpaper-battery-monitor = pkgs.writeShellScriptBin "wallpaper-battery-monitor" ''
    set -euo pipefail

    STATE_DIR="$HOME/.local/state/wallpaper"
    mkdir -p "$STATE_DIR"
    echo $$ > "$STATE_DIR/battery-monitor.pid"

    trap 'rm -f "$STATE_DIR/battery-monitor.pid"' EXIT

    get_ac_online() {
        for ps in /sys/class/power_supply/*/; do
            if [ "$(cat "$ps/type" 2>/dev/null)" = "Mains" ]; then
                cat "$ps/online" 2>/dev/null
                return
            fi
        done
        echo "-1"
    }

    prev_state="unknown"
    while true; do
        state=$(get_ac_online)
        if [ "$state" != "$prev_state" ] && [ "$prev_state" != "unknown" ]; then
            if [ "$state" = "0" ]; then
                # Switched to battery
                if [ ! -f "$STATE_DIR/battery-override" ]; then
                    current_mode=$(cat "$STATE_DIR/mode" 2>/dev/null || echo "static")
                    current_file=$(cat "$STATE_DIR/current-file" 2>/dev/null || echo "")
                    if [ "$current_mode" != "static" ]; then
                        echo "$current_mode $current_file" > "$STATE_DIR/last-animated-mode"
                        wallpaper-set static ~/nix-config/assets/wallpaper.png
                    fi
                fi
            elif [ "$state" = "1" ]; then
                # Switched to AC
                rm -f "$STATE_DIR/battery-override"
                if [ -f "$STATE_DIR/last-animated-mode" ]; then
                    read -r restore_mode restore_file < "$STATE_DIR/last-animated-mode"
                    wallpaper-set "$restore_mode" "$restore_file"
                    rm -f "$STATE_DIR/last-animated-mode"
                fi
            fi
        fi
        prev_state="$state"
        sleep 5
    done
  '';

  wallpaper-restore = pkgs.writeShellScriptBin "wallpaper-restore" ''
    set -euo pipefail

    STATE_DIR="$HOME/.local/state/wallpaper"
    MODE="$(cat "$STATE_DIR/mode" 2>/dev/null || echo "static")"
    FILE="$(cat "$STATE_DIR/current-file" 2>/dev/null || echo "$HOME/nix-config/assets/wallpaper.png")"

    wallpaper-set "$MODE" "$FILE"
  '';
in
{
  home.packages = with pkgs; [
    swww
    mpvpaper
    jq
    wallpaper-set
    wallpaper-menu
    wallpaper-init
    wallpaper-battery-monitor
    wallpaper-restore
  ];
}
