#!/usr/bin/env python3
"""cua-daemon — computer-use-agent seat broker for Hyprland.

Harness-agnostic backend for the `cua` CLI. Owns the single Wayland seat as a
serialized lease, maintains a target registry (real desktop / spawned headless
outputs / workspaces), and performs perception (grim) and action (ydotool/wtype)
on behalf of whichever agent holds the lease.

Mirrors the agent-status daemon (home/linux/agent-status.nix): pure-stdlib
python, a resident loop, atomic JSON publish to $XDG_RUNTIME_DIR every tick
(mtime = heartbeat), fail-soft (the loop never dies on a transient error).

Unlike agent-status (poll-only), action verbs need synchronous replies, so the
daemon also listens on a Unix stream socket ($XDG_RUNTIME_DIR/cua.sock) for the
CLI. Read-only state still goes through the JSON file so waybar / the lock screen
poll it exactly like agent-status.

Design notes:
- The seat is Hyprland's single seat. All action is serialized; only the lease
  holder may inject. This is Approach A (serialized single seat) from the
  requirements; nested per-agent compositors and the a11y `see --tree` fallback
  are deliberately deferred.
- The real desktop is push-to-grant: an agent can never `acquire real` without a
  standing grant minted by the *user* (a non-agent peer or the panic/grant
  keybind). Sandboxes (spawned outputs/workspaces) are self-serve.
- Panic is a hard guarantee implemented out-of-band by killing ydotoold (see
  cua-panic.sh); this daemon only force-clears the lease when it notices the
  revoke touchfile or a dead ydotoold. Lockout (parking the user's physical
  input) is best-effort via `hyprctl keyword device[..]:enabled false`.
"""

import json
import os
import select
import signal
import secrets
import socket
import struct
import subprocess
import sys
import time
import traceback

HOST = os.uname().nodename
RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
STATUS_PATH = os.path.join(RUNTIME, "cua-status.json")
SOCK_PATH = os.path.join(RUNTIME, "cua.sock")
REVOKE_FLAG = os.path.join(RUNTIME, "cua.lease.revoked")
LOCKED_STATE = os.path.join(RUNTIME, "cua.locked-devices")
YDOTOOL_SOCKET = os.path.join(RUNTIME, ".ydotool_socket")
GRANT_TOKEN_PATH = os.path.join(RUNTIME, "cua.grant.token")
# Agent-mode lock (R17): the user's workspaces are migrated to an off-screen
# headless "stage" while a curtain holds the physical output, so agents keep
# full CUA (see+act) on the real desktop while a passerby sees only the lock.
# This record lets a restarted daemon recover (move workspaces back, drop stage)
# rather than leave the user stranded behind a curtain.
AGENT_MODE_STATE = os.path.join(RUNTIME, "cua.agent-mode")
CURTAIN_CLASS = "cua-curtain"
SUBMAP_AGENTLOCK = "agentlock"

LEASE_TIMEOUT_S = 300        # idle lease auto-expiry (5 min)
MAX_SANDBOX_TARGETS = 2      # cap headless outputs on the Radeon 680M
TICK_S = 1.0

# Agent identity by wrapped comm (see docs/agent-status.md "Process detection").
COMM_MATCH = {
    ".claude-wrapped": "claude",
    ".codex-wrapped": "codex",
    ".opencode-wrapp": "opencode",
}

# ydotool click bitmask: 0x40 down | 0x80 up = full click; low nibble = button.
CLICK_CODES = {"left": "0xC0", "right": "0xC1", "middle": "0xC2"}


def log(msg):
    print(f"cua-daemon: {msg}", file=sys.stderr, flush=True)


# ── environment discovery ────────────────────────────────────────────────────
# The daemon runs as a graphical-session systemd user service, which may not
# inherit WAYLAND_DISPLAY / HYPRLAND_INSTANCE_SIGNATURE. Discover them from the
# runtime dir so the daemon is self-sufficient regardless of env import.

def discover_env():
    os.environ.setdefault("YDOTOOL_SOCKET", YDOTOOL_SOCKET)
    if not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
        hypr_dir = os.path.join(RUNTIME, "hypr")
        try:
            sigs = [
                (d, os.path.getmtime(os.path.join(hypr_dir, d)))
                for d in os.listdir(hypr_dir)
                if os.path.isdir(os.path.join(hypr_dir, d))
            ]
            if sigs:
                sigs.sort(key=lambda x: x[1], reverse=True)
                os.environ["HYPRLAND_INSTANCE_SIGNATURE"] = sigs[0][0]
        except OSError:
            pass
    if not os.environ.get("WAYLAND_DISPLAY"):
        for name in ["wayland-1", "wayland-0"]:
            if os.path.exists(os.path.join(RUNTIME, name)):
                os.environ["WAYLAND_DISPLAY"] = name
                break


# ── subprocess helpers ───────────────────────────────────────────────────────

def run(cmd, timeout=5, check=False):
    """Run a command, return (rc, stdout, stderr). Never raises on failure."""
    try:
        p = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout, check=check
        )
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"
    except Exception as e:  # noqa: BLE001 - fail-soft by contract
        return 1, "", str(e)


def hypr_json(*args):
    rc, out, _ = run(["hyprctl", "-j", *args])
    if rc != 0:
        return None
    try:
        return json.loads(out)
    except json.JSONDecodeError:
        return None


def hypr_dispatch(*args):
    return run(["hyprctl", "dispatch", *args])[0] == 0


# ── /proc walking for peer identity ──────────────────────────────────────────

def proc_comm(pid):
    try:
        with open(f"/proc/{pid}/comm") as f:
            return f.read().strip()
    except OSError:
        return None


def proc_ppid(pid):
    try:
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("PPid:"):
                    return int(line.split()[1])
    except (OSError, ValueError):
        pass
    return None


def proc_is_gemini(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return b"gemini.js" in f.read()
    except OSError:
        return False


def agent_for_pid(pid):
    """Walk the parent chain; return the agent name owning this process, or None.

    None means the peer is not one of the four agents — i.e. a plain user shell
    or the Hyprland keybind. That distinction is what enforces push-to-grant:
    only a non-agent peer may `grant`/`revoke` the real desktop (R12).
    """
    seen = 0
    while pid and pid > 1 and seen < 24:
        comm = proc_comm(pid)
        if comm in COMM_MATCH:
            return COMM_MATCH[comm]
        if comm == "node" and proc_is_gemini(pid):
            return "gemini"
        pid = proc_ppid(pid)
        seen += 1
    return None


def peer_pid(conn):
    creds = conn.getsockopt(
        socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i")
    )
    pid, _uid, _gid = struct.unpack("3i", creds)
    return pid


# ── daemon state ─────────────────────────────────────────────────────────────

class Daemon:
    def __init__(self):
        # lease: None or dict(holder,target,kind,locked,since,expiresAt)
        self.lease = None
        self.queue = []            # FIFO list of dict(agent,target)
        self.grants = {}           # agent -> dict(target,lock,ts)
        # sandbox targets created at runtime: id -> dict
        self.sandbox = {}
        self._next_id = 1
        # agent-mode lock: None, or dict(stage, primary, workspaces, restoreWs,
        # since). When set, the "real" target lives on the off-screen stage.
        self.agent_mode = None
        # Secret the user grant path must present; set in main() (C1).
        self.grant_token = None
        # Track ydotoold liveness so we only treat a *transition* to dead as a
        # crash/panic — a simply-absent ydotoold (never started, pre-relogin)
        # must not spuriously clear a held sandbox lease.
        self._ydotool_alive = self._ydotool_reachable()

    # ---- targets -----------------------------------------------------------
    def real_target(self):
        # In agent-mode the real desktop has been migrated to the off-screen
        # stage; "real" then resolves there so see/act capture and inject the
        # user's actual windows (not the curtain on the physical output). It is
        # still push-to-grant and still flagged sandbox=False (an agent acting
        # here IS driving the real desktop, just staged).
        if self.agent_mode:
            return {"id": "real", "kind": "real",
                    "output": self.agent_mode["stage"],
                    "workspace": None, "sandbox": False, "staged": True}
        mons = hypr_json("monitors") or []
        focused = next((m for m in mons if m.get("focused")), mons[0] if mons else None)
        out = focused.get("name") if focused else "eDP-1"
        return {"id": "real", "kind": "real", "output": out,
                "workspace": None, "sandbox": False}

    def _prune_sandboxes(self):
        # Drop sandboxes whose headless output disappeared (removed under us).
        live_outputs = {m.get("name") for m in (hypr_json("monitors all") or [])}
        for tid in list(self.sandbox):
            t = self.sandbox[tid]
            if t["kind"] == "headless" and t["output"] not in live_outputs:
                del self.sandbox[tid]

    def all_targets(self):
        self._prune_sandboxes()
        return [self.real_target(), *self.sandbox.values()]

    def resolve(self, tid):
        if tid in (None, "", "real"):
            return self.real_target()
        if tid in self.sandbox:
            return dict(self.sandbox[tid])
        return None

    def output_offset(self, output):
        for m in (hypr_json("monitors all") or []):
            if m.get("name") == output:
                return int(m.get("x", 0)), int(m.get("y", 0))
        return 0, 0

    def output_scale(self, output):
        # grim writes the PHYSICAL (scaled) buffer; the compositor pointer space
        # is LOGICAL. Clicks must divide PNG-pixel coords by scale (H6 — this
        # host runs scale 2, so without this clicks land at 2x offset).
        for m in (hypr_json("monitors all") or []):
            if m.get("name") == output:
                try:
                    return float(m.get("scale", 1.0)) or 1.0
                except (TypeError, ValueError):
                    return 1.0
        return 1.0

    # ---- lockout (best-effort, R15) ----------------------------------------
    # We disable the POINTER devices only, never the keyboards. Disabling the
    # keyboard would also kill the physical panic keybind (R14) — panic must
    # never deadlock. Full keyboard parking (so the user can't type into the
    # agent's target) is intentionally deferred to the optional EVIOCGRAB+chord
    # helper, which can swallow physical keys while still watching for the panic
    # chord to release itself. So in v1, R15 parks the pointer; the keyboard
    # stays live. Documented in docs/cua.md.
    def lock_input(self):
        devs = hypr_json("devices") or {}
        names = []
        for kind in ("mice",):
            for d in devs.get(kind, []):
                n = d.get("name", "")
                if n and "ydotool" not in n.lower() and "virtual" not in n.lower():
                    names.append(n)
        disabled = []
        for n in names:
            if run(["hyprctl", "keyword", f"device[{n}]:enabled", "false"])[0] == 0:
                disabled.append(n)
        try:
            with open(LOCKED_STATE, "w") as f:
                f.write("\n".join(disabled))
        except OSError:
            pass
        if not disabled:
            log("lockout requested but no devices disabled (best-effort layer failed)")

    def unlock_input(self):
        try:
            with open(LOCKED_STATE) as f:
                names = [n for n in f.read().splitlines() if n]
        except OSError:
            names = []
        for n in names:
            run(["hyprctl", "keyword", f"device[{n}]:enabled", "true"])
        try:
            os.remove(LOCKED_STATE)
        except OSError:
            pass

    # ---- lease transitions -------------------------------------------------
    def _start_lease(self, agent, target, kind, locked):
        now = time.time()
        self.lease = {
            "holder": agent,
            "target": target["id"],
            "kind": kind,
            "locked": locked,
            "since": iso(now),
            "expiresAt": iso(now + LEASE_TIMEOUT_S),
            "expiresEpoch": now + LEASE_TIMEOUT_S,   # numeric, DST-safe (M5)
        }
        if locked:
            self.lock_input()

    def _end_lease(self, promote=False):
        # Always attempt unlock (idempotent; no-op if nothing was locked) so a
        # panic with no lease still re-enables devices.
        self.unlock_input()
        self.lease = None
        try:
            os.remove(REVOKE_FLAG)
        except OSError:
            pass
        # Promote the next waiter ONLY on voluntary release/expiry — never on
        # panic/revoke/shutdown/vanished-output, where the user wants the seat
        # genuinely free (M2).
        if promote:
            self._promote_queue()

    def _promote_queue(self):
        while self.queue and self.lease is None:
            head = self.queue.pop(0)
            target = self.resolve(head["target"])
            if target is None:
                continue
            if not target["sandbox"]:
                # real still needs a standing grant to be promoted
                g = self.grants.get(head["agent"])
                if not (g and g["target"] == "real"):
                    continue
                self.grants.pop(head["agent"], None)
                self._start_lease(head["agent"], target, "granted", g.get("lock", False))
            else:
                self._start_lease(head["agent"], target, "acquired", False)

    # ---- agent-mode lock (R17, output-swap) --------------------------------
    # A cooperative privacy lock that, unlike hyprlock's ext-session-lock, keeps
    # the real desktop live and capturable: the user's workspaces are moved to an
    # off-screen headless "stage" and a curtain holds the physical output. Agents
    # then drive "real" (now the stage) with the existing headless-target path —
    # no flicker, full see+act. NOT a security boundary; see docs/cua.md.
    def _physical_monitors(self):
        return [m for m in (hypr_json("monitors all") or [])
                if not str(m.get("name", "")).startswith("HEADLESS")]

    def _agentmode_status(self):
        if not self.agent_mode:
            return {"active": False}
        return {"active": True, "stage": self.agent_mode["stage"],
                "primary": self.agent_mode["primary"],
                "since": self.agent_mode["since"]}

    def _persist_agentmode(self):
        try:
            atomic_write(AGENT_MODE_STATE, self.agent_mode)
        except OSError:
            pass

    def v_agentmode(self, req, agent_name):
        # Entering/leaving agent-mode is a USER action (it parks the user's own
        # input and stages their desktop). Reject agents — same fail-closed
        # identity rule as grant/revoke, so a compromised agent can't lock the
        # user out or, worse, lift the curtain on itself.
        if agent_name is not None:
            return err("agents cannot toggle agent-mode", "FORBIDDEN")
        if req.get("on"):
            return self._agentmode_enter()
        return self._agentmode_exit()

    def _agentmode_enter(self):
        if self.agent_mode:
            return ok(agentMode=self._agentmode_status(), already=True)
        # Agent-mode is an ALTERNATIVE to hyprlock, not an overlay on it. A real
        # ext-session-lock blanks every output from grim — including the stage —
        # so entering under hyprlock would be half-broken (agents blinded).
        # Refuse with a clear message; the user unlocks first, then locks here.
        if run(["hyprctl", "locked"])[1].strip().lower() == "true":
            return err("hyprlock is active — unlock it first; agent-mode replaces "
                       "hyprlock (it can't capture under an ext-session-lock)",
                       "ALREADY_LOCKED")
        mons = self._physical_monitors()
        if not mons:
            return err("no physical monitor to lock", "NO_MONITOR")
        prim = next((m for m in mons if m.get("focused")), mons[0])
        pname = prim["name"]
        # Stop hypridle so its idle timeout can't fire hyprlock mid-agent-mode and
        # slap a real ext-session-lock over everything (which would blank the
        # stage). Teardown restarts it. (Also pauses auto-dpms/dim — fine while
        # the curtain owns the screen.)
        run(["systemctl", "--user", "stop", "hypridle.service"])
        # Snapshot what to migrate + restore BEFORE touching the layout.
        restore_ws = (hypr_json("activeworkspace") or {}).get("id")
        moved = [w["id"] for w in (hypr_json("workspaces") or [])
                 if w.get("monitor") == pname and isinstance(w.get("id"), int)
                 and w["id"] >= 0]
        # 1. off-screen stage, matched to the physical geometry so PNG pixels and
        #    click coords map 1:1 with the real output.
        before = {m.get("name") for m in (hypr_json("monitors all") or [])}
        run(["hyprctl", "output", "create", "headless"])
        time.sleep(0.3)
        after = {m.get("name") for m in (hypr_json("monitors all") or [])}
        new = sorted(after - before)
        if not new:
            return err("agent-mode stage was not created", "SPAWN_FAILED")
        stage = new[0]
        w, h = int(prim.get("width", 1920)), int(prim.get("height", 1080))
        try:
            hz = int(round(float(prim.get("refreshRate", 60)) or 60))
        except (TypeError, ValueError):
            hz = 60
        scale = prim.get("scale", 1.0)
        run(["hyprctl", "keyword", "monitor", f"{stage},{w}x{h}@{hz},auto,{scale}"])
        time.sleep(0.2)
        # 2. migrate every physical-output workspace onto the stage.
        for wid in moved:
            run(["hyprctl", "dispatch", "moveworkspacetomonitor",
                 f"{wid} {stage}"])
        # 3. raise the curtain on the now-empty physical output, fullscreen.
        run(["hyprctl", "dispatch", "focusmonitor", pname])
        run(["hyprctl", "dispatch", "exec",
             f"[fullscreen] kitty --class {CURTAIN_CLASS} -T 'AGENT MODE' cua-curtain"])
        # 4. lock down human input: the agentlock submap kills every keybind but
        #    panic/unlock; the pointer is parked. (Keyboard is never *disabled* —
        #    the panic chord must always fire; the submap makes stray keys inert.)
        run(["hyprctl", "dispatch", "submap", SUBMAP_AGENTLOCK])
        self.lock_input()
        # 5. record + persist for crash recovery.
        self.agent_mode = {"stage": stage, "primary": pname,
                           "workspaces": moved, "restoreWs": restore_ws,
                           "since": iso(time.time())}
        self._persist_agentmode()
        log(f"agent-mode ON: staged {len(moved)} ws on {stage}, curtain on {pname}")
        return ok(agentMode=self._agentmode_status())

    def _agentmode_teardown(self, am):
        # Idempotent restore of one agent-mode record. Order matters: release the
        # input lockdown FIRST so a failure in a later step can never leave the
        # user stuck behind a curtain with dead keybinds.
        run(["hyprctl", "dispatch", "submap", "reset"])
        self.unlock_input()
        run(["hyprctl", "dispatch", "closewindow", f"class:{CURTAIN_CLASS}"])
        live = {m.get("name") for m in (hypr_json("monitors all") or [])}
        prim = am.get("primary")
        # Move the user's workspaces back to the physical output, THEN drop the
        # stage. (If the stage is already gone, Hyprland has auto-fallen the
        # workspaces back to a live monitor — the move is then a harmless no-op.)
        for wid in am.get("workspaces", []):
            run(["hyprctl", "dispatch", "moveworkspacetomonitor",
                 f"{wid} {prim}"])
        if am.get("stage") in live:
            run(["hyprctl", "output", "remove", am["stage"]])
        if am.get("restoreWs") is not None:
            run(["hyprctl", "dispatch", "workspace", str(am["restoreWs"])])
        # Hand idle management back (auto-lock/dpms/dim) now that the desktop is
        # the user's again. Always restart — covers exit, panic, and recovery.
        run(["systemctl", "--user", "start", "hypridle.service"])

    def _agentmode_exit(self):
        am = self.agent_mode
        if not am:
            # No record, but still clear the lockdown primitives in case a stale
            # submap/curtain lingered (defensive; cheap).
            run(["hyprctl", "dispatch", "submap", "reset"])
            return ok(agentMode={"active": False}, already=False)
        # If an agent is mid-drive on the staged real desktop, end its lease so we
        # don't yank the user's view back out from under a live injection.
        if self.lease:
            t = self.resolve(self.lease["target"])
            if t and t.get("id") == "real":
                self._end_lease()
        self._agentmode_teardown(am)
        self.agent_mode = None
        try:
            os.remove(AGENT_MODE_STATE)
        except OSError:
            pass
        log("agent-mode OFF: desktop restored")
        return ok(agentMode={"active": False})

    def recover_agent_mode(self):
        # Startup: tear down any agent-mode a crashed daemon left behind. The
        # user must never boot into a stuck curtain with windows stranded on a
        # removed headless output. Always reset the input lockdown; if a record
        # exists, also migrate workspaces back and drop the stage.
        try:
            with open(AGENT_MODE_STATE) as f:
                am = json.load(f)
        except (OSError, json.JSONDecodeError):
            am = None
        run(["hyprctl", "dispatch", "submap", "reset"])
        run(["hyprctl", "dispatch", "closewindow", f"class:{CURTAIN_CLASS}"])
        if am:
            self._agentmode_teardown(am)
            log("recovered stale agent-mode from a prior run")
        self.agent_mode = None
        try:
            os.remove(AGENT_MODE_STATE)
        except OSError:
            pass

    # ---- verbs -------------------------------------------------------------
    def handle(self, req, agent_name):
        verb = req.get("verb")
        fn = getattr(self, f"v_{verb}", None)
        if fn is None:
            return err(f"unknown verb '{verb}'", "UNKNOWN_VERB")
        try:
            return fn(req, agent_name)
        except Exception as e:  # noqa: BLE001
            log(f"verb {verb} failed: {e}\n{traceback.format_exc()}")
            return err(str(e), "INTERNAL")

    def _require_holder(self, agent_name):
        if self.lease is None:
            return err("no active lease", "NO_LEASE")
        if self.lease["holder"] != agent_name:
            return err(f"seat held by {self.lease['holder']}", "NOT_HOLDER")
        return None

    def _bump(self):
        if self.lease:
            self.lease["expiresEpoch"] = time.time() + LEASE_TIMEOUT_S
            self.lease["expiresAt"] = iso(self.lease["expiresEpoch"])

    def _is_user(self, agent_name, req):
        # A request counts as the user ONLY if the peer is not an agent AND it
        # carries the grant token the daemon wrote at startup. Fail-CLOSED: a
        # /proc read failure or pid-reuse that yields agent_name=None can't be
        # mistaken for the user (C1). Within one UID this is still cooperative —
        # a same-UID process can read the token file. See docs/cua.md.
        return agent_name is None and req.get("token") == self.grant_token

    def v_acquire(self, req, agent_name):
        agent = agent_name or req.get("agent") or "unknown"
        target = self.resolve(req.get("target"))
        if target is None:
            return err("unknown target", "UNKNOWN_TARGET")
        # real always needs a standing grant — even to queue (M4: don't hand out
        # a phantom queue slot _promote_queue would skip forever).
        grant = None
        if not target["sandbox"]:
            grant = self.grants.get(agent)
            if not (grant and grant["target"] == "real"):
                return err("real desktop requires a grant (push-to-grant)", "NEEDS_GRANT")
        if self.lease is not None:
            if self.lease["holder"] == agent and self.lease["target"] == target["id"]:
                return ok(lease=self.lease)
            self.queue.append({"agent": agent, "target": target["id"]})
            return ok(queued=True, position=len(self.queue))
        if not target["sandbox"]:
            self.grants.pop(agent, None)
            self._start_lease(agent, target, "granted", grant.get("lock", False))
        else:
            self._start_lease(agent, target, "acquired", False)
        return ok(lease=self.lease)

    def v_release(self, req, agent_name):
        e = self._require_holder(agent_name)
        if e:
            return e
        self._end_lease(promote=True)   # voluntary -> next waiter may take it
        return ok(released=True)

    def v_grant(self, req, agent_name):
        if agent_name is not None:
            return err("agents cannot grant the real desktop", "FORBIDDEN")
        if not self._is_user(agent_name, req):
            return err("grant requires the user grant token", "NEEDS_AUTH")
        target = req.get("target", "real")
        agent = req.get("agent")
        if not agent:
            return err("grant requires <agent>", "BAD_ARGS")
        self.grants[agent] = {"target": target, "lock": bool(req.get("lock")),
                              "ts": iso(time.time())}
        return ok(granted={"agent": agent, "target": target, "lock": bool(req.get("lock"))})

    def v_revoke(self, req, agent_name):
        # An agent may revoke only its OWN active lease. Clearing grants or
        # another holder's lease requires the user grant token (fail-closed).
        if agent_name is not None:
            if self.lease and self.lease["holder"] == agent_name:
                self._end_lease()
                return ok(revoked=True)
            return err("agents may only revoke their own lease", "FORBIDDEN")
        if not self._is_user(agent_name, req):
            return err("revoke requires the user grant token", "NEEDS_AUTH")
        target_agent = req.get("agent")
        if target_agent:
            self.grants.pop(target_agent, None)
        if self.lease and (target_agent is None or self.lease["holder"] == target_agent):
            self._end_lease()
        return ok(revoked=True)

    def v_panic(self, req, agent_name):
        # stop (not kill): Restart=always would revive a killed injector within
        # ~1s, possibly before the lease clears. Stop keeps it down; restart only
        # AFTER the seat is released.
        run(["systemctl", "--user", "stop", "ydotoold.service"])
        self._end_lease()   # unlocks devices; per-action restore already ran (H3)
        # Panic is "give me back my computer": if agent-mode is up, also restore
        # the desktop and drop the curtain so the user is never left locked out.
        if self.agent_mode:
            self._agentmode_exit()
        run(["systemctl", "--user", "start", "ydotoold.service"])
        return ok(panicked=True)

    def v_see(self, req, agent_name):
        # No lease required (R8): perception is read-only and non-contending.
        if req.get("tree"):
            return err("see --tree (a11y dump) is not implemented (deferred)", "DEFERRED")
        target = self.resolve(req.get("target"))
        if target is None:
            return err("unknown target", "UNKNOWN_TARGET")
        # Confine --out to RUNTIME by basename only. v_see needs no lease, so an
        # unvalidated caller path would be an unprivileged arbitrary-file-write
        # primitive (H1): `cua see --out /home/.../.bashrc` would overwrite it.
        req_out = req.get("out")
        out_path = os.path.join(
            RUNTIME, os.path.basename(req_out) if req_out
            else f"cua-see-{target['id']}.png")
        region = req.get("region")
        if region:
            rc, _, e = run(["grim", "-g", region, out_path], timeout=10)
        else:
            rc, _, e = run(["grim", "-o", target["output"], out_path], timeout=10)
        if rc != 0:
            return err(f"grim failed: {e}", "CAPTURE_FAILED")
        # Emit scale so the agent can map PNG (physical) pixels to click coords.
        return ok(path=out_path, output=target["output"],
                  scale=self.output_scale(target["output"]))

    def _act_target(self, req, agent_name):
        # Synchronous panic guard: if the revoke flag is set, refuse to inject
        # even before the ~1s tick clears the lease (H5 — closes the window where
        # `type` could still fire after the user hit panic).
        if os.path.exists(REVOKE_FLAG):
            return err("seat revoked", "REVOKED"), None
        e = self._require_holder(agent_name)
        if e:
            return e, None
        target = self.resolve(req.get("target") or self.lease["target"])
        if target is None:
            return err("unknown target", "UNKNOWN_TARGET"), None
        if target["id"] != self.lease["target"]:
            return err("can only act on the held target", "WRONG_TARGET"), None
        return None, target

    def _juggle(self, target):
        # Focus-juggle (save -> focus target -> inject -> restore) only for
        # OFF-screen targets. Normally the real desktop is the focused output
        # already; juggling there reverts the click's own focus so a following
        # `type` lands in the wrong window (H2). In agent-mode, though, "real"
        # has been migrated to the off-screen stage, so it DOES need juggling
        # (the curtain owns the physical output's focus otherwise).
        if target["id"] == "real":
            return self.agent_mode is not None
        return True

    def v_click(self, req, agent_name):
        e, target = self._act_target(req, agent_name)
        if e:
            return e
        juggle = self._juggle(target)
        saved = self.save_focus() if juggle else None
        if juggle:
            self.focus_target(target)
        if "x" in req and "y" in req:
            ox, oy = self.output_offset(target["output"])
            scale = self.output_scale(target["output"])
            gx = int(int(req["x"]) / scale) + ox
            gy = int(int(req["y"]) / scale) + oy
            run(["ydotool", "mousemove", "--absolute", "-x", str(gx), "-y", str(gy)])
        code = CLICK_CODES.get(req.get("button", "left"), "0xC0")
        rc = run(["ydotool", "click", code])[0]
        if juggle:
            self.restore_focus(saved)
        self._bump()
        return ok(clicked=(rc == 0))

    def v_type(self, req, agent_name):
        e, target = self._act_target(req, agent_name)
        if e:
            return e
        text = req.get("text", "")
        juggle = self._juggle(target)
        saved = self.save_focus() if juggle else None
        if juggle:
            self.focus_target(target)
        # ydotool only — the single chokepoint panic kills. wtype is a SEPARATE
        # virtual keyboard a panic would NOT stop, breaking the panic guarantee.
        rc = run(["ydotool", "type", "--key-delay", "12", "--", text], timeout=15)[0]
        if juggle:
            self.restore_focus(saved)
        self._bump()
        return ok(typed=(rc == 0))

    def v_scroll(self, req, agent_name):
        e, target = self._act_target(req, agent_name)
        if e:
            return e
        n = int(req.get("amount", 3))
        if req.get("dir") == "up":
            n = -n
        juggle = self._juggle(target)
        saved = self.save_focus() if juggle else None
        if juggle:
            self.focus_target(target)
        rc = run(["ydotool", "mousemove", "--wheel", "-x", "0", "-y", str(n)])[0]
        if juggle:
            self.restore_focus(saved)
        self._bump()
        return ok(scrolled=(rc == 0))

    def v_key(self, req, agent_name):
        e, target = self._act_target(req, agent_name)
        if e:
            return e
        chord = req.get("chord", "").split()
        if not chord:
            return err("key requires a chord (e.g. '29:1 46:1 46:0 29:0')", "BAD_ARGS")
        juggle = self._juggle(target)
        saved = self.save_focus() if juggle else None
        if juggle:
            self.focus_target(target)
        rc = run(["ydotool", "key", *chord])[0]
        if juggle:
            self.restore_focus(saved)
        self._bump()
        return ok(keyed=(rc == 0))

    def v_target_new(self, req, agent_name):
        # Workspace targets are dropped from v1: a workspace shares the real
        # output, so `grim -o` would capture the user's visible screen (privacy
        # leak) and focusing it would switch the user's view (H7). Headless
        # outputs are the correct isolation primitive.
        if req.get("workspace"):
            return err("workspace targets are not implemented; use --headless", "DEFERRED")
        if len(self.sandbox) >= MAX_SANDBOX_TARGETS:
            return err(f"sandbox target cap reached ({MAX_SANDBOX_TARGETS})", "AT_CAP")
        tid = f"sandbox-{self._next_id}"
        self._next_id += 1
        before = {m.get("name") for m in (hypr_json("monitors all") or [])}
        run(["hyprctl", "output", "create", "headless"])
        time.sleep(0.3)
        after = {m.get("name") for m in (hypr_json("monitors all") or [])}
        new = sorted(after - before)
        if not new:
            return err("headless output was not created", "SPAWN_FAILED")
        output = new[0]
        self.sandbox[tid] = {"id": tid, "kind": "headless", "output": output,
                             "workspace": None, "sandbox": True}
        if req.get("spawn"):
            saved = self.save_focus()
            self.focus_target(self.sandbox[tid])
            hypr_dispatch("exec", req["spawn"])
            self.restore_focus(saved)
        return ok(target=self.sandbox[tid])

    def v_target_rm(self, req, agent_name):
        tid = req.get("target")
        t = self.sandbox.get(tid)
        if t is None:
            return err("not a removable sandbox target", "UNKNOWN_TARGET")
        if t["kind"] == "headless":
            run(["hyprctl", "output", "remove", t["output"]])
        del self.sandbox[tid]
        return ok(removed=tid)

    # ---- focus save/restore (R11) ------------------------------------------
    _saved_focus = None

    def save_focus(self):
        mons = hypr_json("monitors") or []
        mon = next((m for m in mons if m.get("focused")), None)
        aw = hypr_json("activewindow") or {}
        saved = {
            "monitor": mon.get("name") if mon else None,
            "window": aw.get("address") or None,
        }
        self._saved_focus = saved
        return saved

    def focus_target(self, target):
        # Move focus to the target's (off-screen headless) output. Headless
        # targets only — the real desktop never juggles focus (see _juggle).
        if target.get("output"):
            hypr_dispatch("focusmonitor", target["output"])

    def restore_focus(self, saved):
        if saved:
            if saved.get("monitor"):
                hypr_dispatch("focusmonitor", saved["monitor"])
            if saved.get("window"):
                hypr_dispatch("focuswindow", f"address:{saved['window']}")
        # Clear the snapshot so lease-end paths can't later re-restore stale
        # focus and yank the user back to a window they have since left (H3).
        self._saved_focus = None

    # ---- status publish ----------------------------------------------------
    def snapshot(self):
        now = time.time()
        return {
            "updated": iso(now),
            "updatedNs": str(time.time_ns()),
            "host": HOST,
            "driving": self.lease is not None and not self.resolve_is_sandbox(),
            "lease": self.lease,
            "queue": [q["agent"] for q in self.queue],
            "targets": self.all_targets(),
            "grants": {a: g["target"] for a, g in self.grants.items()},
            "agentMode": self._agentmode_status(),
        }

    def resolve_is_sandbox(self):
        if not self.lease:
            return True
        t = self.resolve(self.lease["target"])
        # A vanished target must NOT read as "real" — that would falsely raise
        # the driving alarm and leave a stuck lease (M1).
        if t is None:
            return True
        return bool(t["sandbox"])

    def _ydotool_reachable(self):
        # A SIGKILLed ydotoold leaves a STALE socket file, so file-existence is
        # not liveness (M3). Ask systemd — authoritative and doesn't poke the
        # injector.
        return run(["systemctl", "--user", "is-active", "--quiet",
                    "ydotoold.service"])[0] == 0

    # ---- per-tick maintenance ----------------------------------------------
    def tick(self):
        # out-of-band panic/revoke (cua-panic.sh touches this). No focus restore
        # here — the acting verb already restored and cleared the snapshot (H3).
        if os.path.exists(REVOKE_FLAG):
            self._end_lease()
            # Panic also exits agent-mode (the panic key sets this flag), so the
            # user is never left behind a curtain after smashing panic.
            if self.agent_mode:
                self._agentmode_exit()
            # cua-panic.sh stopped ydotoold so Restart=always couldn't revive it
            # before the lease cleared; now that it has, bring the injector back.
            run(["systemctl", "--user", "start", "ydotoold.service"])
        # ydotoold dying *while we hold the seat* -> force-clear, on a live->dead
        # transition only (an absent-but-never-started ydotoold doesn't clear).
        cur_alive = self._ydotool_reachable()
        if self.lease and self._ydotool_alive and not cur_alive:
            self._end_lease()
        self._ydotool_alive = cur_alive
        # lease target vanished (e.g. headless output removed under us) -> clear
        # so the holder isn't stuck and 'driving' can't false-alarm (M1). Prune
        # first so detection is same-tick, not deferred to the next snapshot().
        self._prune_sandboxes()
        if self.lease and self.resolve(self.lease["target"]) is None:
            self._end_lease()
        # idle expiry — numeric epoch, DST/NTP-safe (M5).
        if self.lease and time.time() > self.lease.get("expiresEpoch", 0):
            self._end_lease()


# ── small helpers ────────────────────────────────────────────────────────────

def iso(epoch):
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(epoch))


def iso_to_epoch(s):
    return time.mktime(time.strptime(s, "%Y-%m-%dT%H:%M:%S"))


def ok(**kw):
    d = {"ok": True}
    d.update(kw)
    return d


def err(msg, code):
    return {"ok": False, "error": msg, "code": code}


def atomic_write(path, obj):
    tmp = f"{path}.tmp.{os.getpid()}"
    with open(tmp, "w") as f:
        json.dump(obj, f)
    os.replace(tmp, path)


# ── main loop ────────────────────────────────────────────────────────────────

def main():
    discover_env()
    daemon = Daemon()
    # Mint the user grant token (0600). The user grant path (CLI / keybind, same
    # UID) reads it; agents are rejected by identity regardless. Fail-closed so a
    # /proc-read failure can't be mistaken for the user (C1).
    daemon.grant_token = secrets.token_hex(16)
    try:
        fd = os.open(GRANT_TOKEN_PATH, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, "w") as f:
            f.write(daemon.grant_token)
    except OSError as e:
        log(f"could not write grant token: {e}")
    # Clear any device lockout left behind by a prior crash (so a wedged-then-
    # restarted daemon never leaves the user's pointer disabled — H4).
    daemon.unlock_input()
    # Likewise tear down any agent-mode a crash left up: never boot the user into
    # a stuck curtain with windows stranded on a removed headless stage (R17).
    daemon.recover_agent_mode()

    if os.path.exists(SOCK_PATH):
        try:
            os.remove(SOCK_PATH)
        except OSError:
            pass
    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    srv.bind(SOCK_PATH)
    os.chmod(SOCK_PATH, 0o600)
    srv.listen(8)

    def shutdown(*_):
        # Unlock devices + clear lease; do NOT promote the queue (M2) or restore
        # stale focus (H3) on the way out. Also exit agent-mode so a stop/restart
        # (e.g. a rebuild) restores the desktop instead of stranding it staged.
        if daemon.agent_mode:
            daemon._agentmode_exit()
        daemon._end_lease()
        for p in (SOCK_PATH, GRANT_TOKEN_PATH):
            try:
                os.remove(p)
            except OSError:
                pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)

    last_tick = 0.0
    log(f"started (status={STATUS_PATH} sock={SOCK_PATH})")
    while True:
        try:
            r, _, _ = select.select([srv], [], [], TICK_S)
            if srv in r:
                conn, _ = srv.accept()
                try:
                    # Short deadline: a same-UID client that connects and stalls
                    # must not block the broker's tick (lease expiry, panic) for long.
                    conn.settimeout(2)
                    data = b""
                    while b"\n" not in data:
                        chunk = conn.recv(4096)
                        if not chunk:
                            break
                        data += chunk
                        if len(data) > 1_000_000:
                            break
                    if data.strip():
                        try:
                            req = json.loads(data.decode().splitlines()[0])
                        except (json.JSONDecodeError, UnicodeDecodeError):
                            resp = err("bad request json", "BAD_JSON")
                        else:
                            agent = agent_for_pid(peer_pid(conn))
                            resp = daemon.handle(req, agent)
                        conn.sendall((json.dumps(resp) + "\n").encode())
                        # republish immediately so reads (target list, status)
                        # reflect this mutation without waiting for the 1s tick
                        try:
                            atomic_write(STATUS_PATH, daemon.snapshot())
                        except Exception:  # noqa: BLE001
                            pass
                except Exception as e:  # noqa: BLE001
                    log(f"connection error: {e}")
                finally:
                    conn.close()

            now = time.monotonic()
            if now - last_tick >= TICK_S:
                last_tick = now
                daemon.tick()
                atomic_write(STATUS_PATH, daemon.snapshot())
        except Exception as e:  # noqa: BLE001 - the loop must never die
            log(f"loop error: {e}\n{traceback.format_exc()}")
            time.sleep(0.5)


if __name__ == "__main__":
    main()
