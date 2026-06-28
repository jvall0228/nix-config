# cua-curtain — the visual "lock" shown on the physical output while agent-mode
# is active (R17). Pure display: it reads cua-status.json + agent-status.json and
# renders a full-screen status board, refreshing every second. It never reads
# stdin, so a passerby's keystrokes do nothing here; the agentlock submap already
# disables every WM keybind but panic/unlock, and the pointer is parked.
#
# The cua daemon spawns this inside a fullscreen kitty (class cua-curtain) and
# closes that window (closewindow class:cua-curtain) on unlock/panic, which kills
# this loop. It is deliberately dependency-light (jq + coreutils) and fail-soft.

set -u
runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
cua="$runtime/cua-status.json"
agents="$runtime/agent-status.json"

# Pre-built SGR sequences (named, so there are no "$var[..]" array-looking
# expansions for shellcheck to flag).
esc=$'\033'
ylw=$'\033[1;33m'; red=$'\033[1;31m'; dim=$'\033[2m'; bold=$'\033[1m'; rst=$'\033[0m'

printf '%s[?25l' "$esc"                               # hide cursor
cleanup() { printf '%s[?25h%s' "$esc" "$rst"; clear 2>/dev/null || true; }
trap cleanup EXIT INT TERM

while :; do
  clear 2>/dev/null || printf '%s[2J%s[H' "$esc" "$esc"
  now=$(date '+%H:%M:%S    %A %b %d')
  stage=$(jq -r '.agentMode.stage // "?"' "$cua" 2>/dev/null || echo "?")
  driver=$(jq -r 'if .driving then "▶  \(.lease.holder) is driving \(.lease.target)" else "" end' \
            "$cua" 2>/dev/null || echo "")
  mapfile -t live < <(jq -r '
      [ (.agents? // {}) | objects | to_entries[] | select(.value.running==true) ][]?
      | "      ●  \(.key)    pid \(.value.pids // [] | map(tostring) | join(","))"
    ' "$agents" 2>/dev/null)

  printf '\n\n\n'
  printf '        %s╔══════════════════════════════════════════╗%s\n' "$ylw" "$rst"
  printf '        %s║          AGENT MODE  —  LOCKED            ║%s\n' "$ylw" "$rst"
  printf '        %s╚══════════════════════════════════════════╝%s\n' "$ylw" "$rst"
  printf '\n        %s%s%s\n\n' "$dim" "$now" "$rst"
  printf '        This screen is locked to you. Background agents keep\n'
  printf '        full computer-use access to your real desktop, which is\n'
  printf '        live on an off-screen stage %s(%s)%s.\n\n' "$dim" "$stage" "$rst"
  printf '        %sActive agents%s\n' "$bold" "$rst"
  if [ "${#live[@]}" -eq 0 ]; then
    printf '      %s  (none running)%s\n' "$dim" "$rst"
  else
    printf '%s\n' "${live[@]}"
  fi
  if [ -n "$driver" ]; then
    printf '\n        %s%s%s\n' "$red" "$driver" "$rst"
  fi
  printf '\n\n        %sSuper+Shift+U%s unlock        %sSuper+Shift+Esc%s panic\n' \
         "$bold" "$rst" "$bold" "$rst"
  sleep 1
done
