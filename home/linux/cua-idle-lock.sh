# cua-idle-lock — hypridle on-timeout router (R17). Decides how the screen locks
# when you idle out:
#   • any agent running  → porous AGENT-MODE  (agents keep computer-use access)
#   • no agents running   → real, authenticated HYPRLOCK
# Policy chosen by the user: route on mere agent presence (agent-status .running).
#
# Fails SAFE: anything unexpected falls through to a real hyprlock — it must never
# leave the screen unlocked. (The daemon stops hypridle only AFTER agent-mode is
# up, so on a failed agent-mode entry this router survives to lock with hyprlock;
# on success the whole hypridle cgroup — including this script — is torn down once
# the curtain is already up, so the trailing hyprlock fallback never fires.)

set -u
runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
status="$runtime/agent-status.json"

# Count running agents the SAME way waybar does — from the `.agents` map, NOT a
# top-level `.running` (which doesn't exist; agent-status.json has no such key).
n=$(jq -r '[ (.agents // {}) | to_entries[] | select(.value.running == true) ] | length' \
      "$status" 2>/dev/null || echo 0)
case "$n" in ''|*[!0-9]*) n=0 ;; esac

if [ "$n" -gt 0 ] && cua agent-mode on >/dev/null 2>&1; then
  exit 0   # agents present and agent-mode engaged → porous lock is up
fi

# No agents, or agent-mode couldn't engage → real secure lock. Use `hyprctl
# locked` (the compositor's session-lock state) rather than `pidof hyprlock`,
# which misses the NixOS `.hyprlock-wrapped` comm and would stack a second lock.
[ "$(hyprctl locked 2>/dev/null)" = "true" ] && exit 0
exec hyprlock
