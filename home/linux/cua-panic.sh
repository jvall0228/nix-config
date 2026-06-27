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

# 1) authoritative kill of the injector (whole cgroup, name-independent)
systemctl --user kill -s KILL ydotoold.service 2>/dev/null || true
# 2) belt-and-suspenders if ydotoold ever runs outside systemd
pkill -9 -f ydotoold 2>/dev/null || true
# 3) tell the cua daemon to stand down (cooperative: clears lease, unlocks input)
: > "$runtime/cua.lease.revoked" 2>/dev/null || true

notify-send -u critical "cua" "panic — seat returned to you" 2>/dev/null || true
