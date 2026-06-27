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

    # ---- targets -----------------------------------------------------------
    def real_target(self):
        mons = hypr_json("monitors") or []
        focused = next((m for m in mons if m.get("focused")), mons[0] if mons else None)
        out = focused.get("name") if focused else "eDP-1"
        return {"id": "real", "kind": "real", "output": out,
                "workspace": None, "sandbox": False}

    def all_targets(self):
        targets = [self.real_target()]
        # prune sandboxes whose output disappeared
        live_outputs = {m.get("name") for m in (hypr_json("monitors all") or [])}
        for tid in list(self.sandbox):
            t = self.sandbox[tid]
            if t["kind"] == "headless" and t["output"] not in live_outputs:
                del self.sandbox[tid]
        targets.extend(self.sandbox.values())
        return targets

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
        }
        if locked:
            self.lock_input()

    def _end_lease(self, restore_focus=True):
        if self.lease and self.lease.get("locked"):
            self.unlock_input()
        self.lease = None
        try:
            os.remove(REVOKE_FLAG)
        except OSError:
            pass
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
            self.lease["expiresAt"] = iso(time.time() + LEASE_TIMEOUT_S)

    def v_acquire(self, req, agent_name):
        agent = agent_name or req.get("agent") or "unknown"
        target = self.resolve(req.get("target"))
        if target is None:
            return err("unknown target", "UNKNOWN_TARGET")
        if self.lease is not None:
            if self.lease["holder"] == agent and self.lease["target"] == target["id"]:
                return ok(lease=self.lease)
            self.queue.append({"agent": agent, "target": target["id"]})
            return ok(queued=True, position=len(self.queue))
        if not target["sandbox"]:
            g = self.grants.get(agent)
            if not (g and g["target"] == "real"):
                return err("real desktop requires a grant (push-to-grant)", "NEEDS_GRANT")
            self.grants.pop(agent, None)
            self._start_lease(agent, target, "granted", g.get("lock", False))
        else:
            self._start_lease(agent, target, "acquired", False)
        return ok(lease=self.lease)

    def v_release(self, req, agent_name):
        e = self._require_holder(agent_name)
        if e:
            return e
        self._end_lease()
        return ok(released=True)

    def v_grant(self, req, agent_name):
        # User authority only: an agent peer may not grant the real desktop.
        if agent_name is not None and req.get("target", "real") == "real":
            return err("agents cannot grant the real desktop", "FORBIDDEN")
        target = req.get("target", "real")
        agent = req.get("agent")
        if not agent:
            return err("grant requires --agent", "BAD_ARGS")
        self.grants[agent] = {"target": target, "lock": bool(req.get("lock")),
                              "ts": iso(time.time())}
        return ok(granted={"agent": agent, "target": target, "lock": bool(req.get("lock"))})

    def v_revoke(self, req, agent_name):
        agent = req.get("agent")
        if agent:
            self.grants.pop(agent, None)
        if self.lease and (agent is None or self.lease["holder"] == agent):
            self.restore_focus(self._saved_focus)
            self._end_lease()
        return ok(revoked=True)

    def v_panic(self, req, agent_name):
        run(["systemctl", "--user", "kill", "-s", "KILL", "ydotoold.service"])
        if self.lease:
            self._end_lease()
        else:
            self.unlock_input()
        return ok(panicked=True)

    def v_see(self, req, agent_name):
        # No lease required (R8): perception is read-only and non-contending.
        if req.get("tree"):
            return err("see --tree (a11y dump) is not implemented (deferred)", "DEFERRED")
        target = self.resolve(req.get("target"))
        if target is None:
            return err("unknown target", "UNKNOWN_TARGET")
        out_path = req.get("out") or os.path.join(
            RUNTIME, f"cua-see-{target['id']}.png")
        region = req.get("region")
        if region:
            rc, _, e = run(["grim", "-g", region, out_path], timeout=10)
        else:
            rc, _, e = run(["grim", "-o", target["output"], out_path], timeout=10)
        if rc != 0:
            return err(f"grim failed: {e}", "CAPTURE_FAILED")
        return ok(path=out_path, output=target["output"])

    def _act_target(self, req, agent_name):
        e = self._require_holder(agent_name)
        if e:
            return e, None
        target = self.resolve(req.get("target") or self.lease["target"])
        if target is None:
            return err("unknown target", "UNKNOWN_TARGET"), None
        if target["id"] != self.lease["target"]:
            return err("can only act on the held target", "WRONG_TARGET"), None
        return None, target

    def v_click(self, req, agent_name):
        e, target = self._act_target(req, agent_name)
        if e:
            return e
        saved = self.save_focus()
        self.focus_target(target)
        if "x" in req and "y" in req:
            ox, oy = self.output_offset(target["output"])
            run(["ydotool", "mousemove", "--absolute", "-x",
                 str(int(req["x"]) + ox), "-y", str(int(req["y"]) + oy)])
        code = CLICK_CODES.get(req.get("button", "left"), "0xC0")
        rc = run(["ydotool", "click", code])[0]
        self.restore_focus(saved)
        self._bump()
        return ok(clicked=(rc == 0))

    def v_type(self, req, agent_name):
        e, target = self._act_target(req, agent_name)
        if e:
            return e
        text = req.get("text", "")
        saved = self.save_focus()
        self.focus_target(target)
        # Prefer wtype (Wayland virtual keyboard, no uinput); ydotool fallback.
        rc = run(["wtype", "--", text], timeout=15)[0]
        if rc != 0:
            rc = run(["ydotool", "type", "--key-delay", "12", "--", text], timeout=15)[0]
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
        saved = self.save_focus()
        self.focus_target(target)
        rc = run(["ydotool", "mousemove", "--wheel", "-x", "0", "-y", str(n)])[0]
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
        saved = self.save_focus()
        self.focus_target(target)
        rc = run(["ydotool", "key", *chord])[0]
        self.restore_focus(saved)
        self._bump()
        return ok(keyed=(rc == 0))

    def v_target_new(self, req, agent_name):
        if len(self.sandbox) >= MAX_SANDBOX_TARGETS:
            return err(f"sandbox target cap reached ({MAX_SANDBOX_TARGETS})", "AT_CAP")
        tid = f"sandbox-{self._next_id}"
        self._next_id += 1
        if req.get("workspace"):
            wsname = f"cua-{tid}"
            self.sandbox[tid] = {"id": tid, "kind": "workspace",
                                 "output": self.real_target()["output"],
                                 "workspace": f"name:{wsname}", "sandbox": True}
        else:
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
        # Move keyboard/pointer focus to the target's output without switching
        # the user's *visible* workspace (headless lives off-screen). For a
        # workspace target, focus its workspace silently.
        if target.get("output"):
            hypr_dispatch("focusmonitor", target["output"])
        if target.get("kind") == "workspace" and target.get("workspace"):
            hypr_dispatch("workspace", target["workspace"])

    def restore_focus(self, saved):
        if not saved:
            return
        if saved.get("monitor"):
            hypr_dispatch("focusmonitor", saved["monitor"])
        if saved.get("window"):
            hypr_dispatch("focuswindow", f"address:{saved['window']}")

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
        }

    def resolve_is_sandbox(self):
        if not self.lease:
            return True
        t = self.resolve(self.lease["target"])
        return bool(t and t["sandbox"])

    # ---- per-tick maintenance ----------------------------------------------
    def tick(self):
        # honor an out-of-band panic/revoke (cua-panic.sh touches this)
        if os.path.exists(REVOKE_FLAG):
            if self.lease:
                self.restore_focus(self._saved_focus)
            self._end_lease()
        # ydotoold died (e.g. panic) -> force-clear an active lease
        if self.lease and not os.path.exists(YDOTOOL_SOCKET):
            self.restore_focus(self._saved_focus)
            self._end_lease()
        # expire idle lease
        if self.lease:
            try:
                if time.time() > iso_to_epoch(self.lease["expiresAt"]):
                    self.restore_focus(self._saved_focus)
                    self._end_lease()
            except Exception:  # noqa: BLE001
                pass


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
        if daemon.lease:
            daemon.restore_focus(daemon._saved_focus)
            daemon._end_lease()
        try:
            os.remove(SOCK_PATH)
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
                    conn.settimeout(5)
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
