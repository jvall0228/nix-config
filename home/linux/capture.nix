{ pkgs, ... }:
let
  capture-menu = pkgs.writeShellScriptBin "capture-menu" ''
    STATE_DIR="$HOME/.local/state/capture"
    PID_FILE="$STATE_DIR/recording.pid"
    PATH_FILE="$STATE_DIR/recording.path"
    SCREENSHOT_DIR="$HOME/Pictures/Screenshots"
    RECORDING_DIR="$HOME/Videos/Recordings"

    mkdir -p "$STATE_DIR"

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

    stop_recording() {
        if pid_alive "$PID_FILE"; then
            local pid
            pid="$(cat "$PID_FILE")"
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
            local saved_path
            saved_path="$(cat "$PATH_FILE" 2>/dev/null || echo "")"
            rm -f "$PID_FILE" "$PATH_FILE"
            if [ -n "$saved_path" ]; then
                notify-send "Capture" "Recording saved to $saved_path"
            fi
            return 0
        fi
        # Stale state cleanup
        rm -f "$PID_FILE" "$PATH_FILE"
        return 1
    }

    do_screenshot_region() {
        local geometry
        geometry="$(slurp 2>/dev/null)" || exit 0
        grim -g "$geometry" - | wl-copy
        notify-send "Capture" "Screenshot copied to clipboard"
    }

    do_screenshot_fullscreen() {
        mkdir -p "$SCREENSHOT_DIR"
        local filename="screenshot-$(date +%Y%m%d-%H%M%S).png"
        local filepath="$SCREENSHOT_DIR/$filename"
        grim "$filepath"
        wl-copy < "$filepath"
        notify-send "Capture" "Screenshot saved to $filepath"
    }

    do_record_region() {
        # Stop any active recording first
        stop_recording 2>/dev/null || true

        local geometry
        geometry="$(slurp 2>/dev/null)" || exit 0

        mkdir -p "$RECORDING_DIR"
        local filename="recording-$(date +%Y%m%d-%H%M%S).mp4"
        local filepath="$RECORDING_DIR/$filename"
        echo "$filepath" > "$PATH_FILE"

        wl-screenrec -g "$geometry" --audio -f "$filepath" &
        echo $! > "$PID_FILE"
        disown
        notify-send "Capture" "Recording started"
    }

    do_record_fullscreen() {
        # Stop any active recording first
        stop_recording 2>/dev/null || true

        mkdir -p "$RECORDING_DIR"
        local filename="recording-$(date +%Y%m%d-%H%M%S).mp4"
        local filepath="$RECORDING_DIR/$filename"
        echo "$filepath" > "$PATH_FILE"

        wl-screenrec --audio -f "$filepath" &
        echo $! > "$PID_FILE"
        disown
        notify-send "Capture" "Recording started"
    }

    do_stop_recording() {
        if ! stop_recording; then
            notify-send "Capture" "No active recording"
        fi
    }

    # Initial call — show menu
    if [ "''${ROFI_RETV:-0}" -eq 0 ]; then
        printf '\0prompt\x1fCapture\n'
        printf 'Screenshot Region\0icon\x1fedit-select\x1finfo\x1fscreenshot_region\n'
        printf 'Screenshot Fullscreen\0icon\x1fview-fullscreen\x1finfo\x1fscreenshot_fullscreen\n'
        printf 'Record Region\0icon\x1fmedia-record\x1finfo\x1frecord_region\n'
        printf 'Record Fullscreen\0icon\x1fmedia-record\x1finfo\x1frecord_fullscreen\n'
        printf 'Stop Recording\0icon\x1fmedia-playback-stop\x1finfo\x1fstop_recording\n'
        exit 0
    fi

    # User selected an entry
    if [ "''${ROFI_RETV:-0}" -eq 1 ]; then
        case "''${ROFI_INFO:-}" in
            screenshot_region)
                do_screenshot_region
                ;;
            screenshot_fullscreen)
                do_screenshot_fullscreen
                ;;
            record_region)
                do_record_region
                ;;
            record_fullscreen)
                do_record_fullscreen
                ;;
            stop_recording)
                do_stop_recording
                ;;
        esac
        exit 0
    fi
  '';
in
{
  home.packages = with pkgs; [
    libnotify
    capture-menu
  ];
}
