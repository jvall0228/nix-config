# cua-panic — instantly return the seat to the user (R14).
#
# The single chokepoint for all agent input is ydotoold: killing it destroys the
# uinput device, so the kernel synthesizes key/button releases (no stuck
# modifiers) and any in-flight `ydotool` call fails immediately. This is the hard
# guarantee. SIGKILL to the systemd cgroup is name-independent — it sidesteps the
# NixOS `.ydotoold-wrapped` comm rename that defeats `pkill -x`.
#
# We deliberately do NOT re-enable input devices or clear the lease here: the cua
# daemon notices the revoke flag (and the dead ydotool socket) on its next ~1s
# tick and does the unlock + focus-restore + lease-clear itself. Keeping panic
# minimal means it has no dependency on the daemon being healthy to stop input.

set -u
runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# 1) STOP (not kill) the injector. A kill would be revived by Restart=always
#    within ~1s, possibly before the lease clears; an explicit stop keeps it
#    down until the cua daemon restarts it after releasing the seat.
systemctl --user stop ydotoold.service 2>/dev/null || true
# 2) belt-and-suspenders if ydotoold ever runs outside systemd
pkill -9 -f ydotoold 2>/dev/null || true
# 3) Independently re-enable any devices the lockout disabled — do NOT depend on
#    the daemon being healthy to hand the user's input back.
state="$runtime/cua.locked-devices"
if [ -f "$state" ] && command -v hyprctl >/dev/null 2>&1; then
  while IFS= read -r dev; do
    [ -n "$dev" ] || continue
    hyprctl keyword "device[$dev]:enabled" true >/dev/null 2>&1 || true
  done < "$state"
  rm -f "$state" 2>/dev/null || true
fi
# 4) Agent-mode lock (R17): independently lift the input lockdown so the panic
#    chord restores the user's keyboard even if the daemon is dead — reset the
#    submap (re-enables all normal keybinds) and drop the curtain so the physical
#    screen is usable again. The daemon, on its next tick (or restart), migrates
#    the staged workspaces back and removes the stage; we don't remove headless
#    outputs here so a stray panic can't nuke unrelated sandbox targets.
if command -v hyprctl >/dev/null 2>&1; then
  hyprctl dispatch submap reset >/dev/null 2>&1 || true
  hyprctl dispatch closewindow "class:cua-curtain" >/dev/null 2>&1 || true
fi

# 5) tell the cua daemon to stand down (clears lease, exits agent-mode, restarts
#    the injector)
: > "$runtime/cua.lease.revoked" 2>/dev/null || true

notify-send -u critical "cua" "panic — seat returned to you" 2>/dev/null || true
