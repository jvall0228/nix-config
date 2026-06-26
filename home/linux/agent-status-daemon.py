#!/usr/bin/env python3
"""agent-status daemon — single source of truth for AI-agent status on this machine.

Long-running loop (~1 Hz). Detects every AI-agent CLI by its process name, and for
each RUNNING agent extracts the latest user/assistant message from that agent's own
session store. Publishes a canonical JSON to $XDG_RUNTIME_DIR/agent-status.json,
written atomically every tick. Consumers poll the file (no signals/pushes), and use
its mtime as a heartbeat to tell a live daemon from a dead one.

Consumers (hyprlock lock screen, waybar, scripts) read the JSON; none of them need
to re-implement process detection or transcript parsing. This daemon authenticates
to nothing — it only reads local process state and local session files.

Process detection (verified): Nix wraps three of the four binaries with makeCWrapper,
so the running process comm is ".<name>-wrapped" (truncated to 15 chars), not "<name>":
  claude    -> comm ".claude-wrapped"
  codex     -> comm ".codex-wrapped"
  opencode  -> comm ".opencode-wrapp"   (15-char TASK_COMM_LEN truncation)
  gemini    -> a node process; match "gemini.js" in the cmdline instead
"""

import json
import os
import re
import signal
import socket
import sqlite3
import sys
import textwrap
import time

HOME = os.path.expanduser("~")
RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())
OUT = os.path.join(RUNTIME, "agent-status.json")
HOSTNAME = socket.gethostname()

# Human-facing names for the lock-screen "speaker" line, per agent.
DISPLAY = {"claude": "Claude", "codex": "Codex", "gemini": "Gemini", "opencode": "Opencode"}
OPENCODE_DB = os.path.join(HOME, ".local", "share", "opencode", "opencode.db")

# ---------------------------------------------------------------------------
# Process detection — scan /proc directly (no pgrep fork per tick).
# ---------------------------------------------------------------------------

# comm-based matchers (exact comm match). gemini handled separately via cmdline.
COMM_MATCH = {
    "claude": ".claude-wrapped",
    "codex": ".codex-wrapped",
    "opencode": ".opencode-wrapp",
}

# gemini runs as a node process; match gemini.js at a path/word boundary so a node
# tool merely referencing a file like "notgemini.js" isn't a false positive.
GEMINI_RE = re.compile(r"(?:^|/)gemini\.js(?:\s|$)")


def scan_procs():
    """Return {agent_name: [pid, ...]} for every running agent."""
    found = {name: [] for name in ("claude", "codex", "gemini", "opencode")}
    mypid = os.getpid()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        if pid == mypid:
            continue
        try:
            with open("/proc/%s/comm" % entry, "r") as f:
                comm = f.read().rstrip("\n")
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            continue
        matched = False
        for name, want in COMM_MATCH.items():
            if comm == want:
                found[name].append(pid)
                matched = True
                break
        if matched:
            continue
        # gemini runs as `node ... gemini.js`; inspect cmdline.
        if comm in ("node", "node-22", ".node-wrapped"):
            try:
                with open("/proc/%s/cmdline" % entry, "rb") as f:
                    cmdline = f.read().replace(b"\x00", b" ").decode("utf-8", "replace")
            except (FileNotFoundError, ProcessLookupError, PermissionError):
                continue
            if GEMINI_RE.search(cmdline):
                found["gemini"].append(pid)
    return found


# ---------------------------------------------------------------------------
# Per-agent transcript extraction. Each returns a dict (possibly partial) or {}.
# ---------------------------------------------------------------------------

def _newest(paths):
    best, best_mt = None, -1.0
    for p in paths:
        try:
            mt = os.path.getmtime(p)
        except OSError:
            continue
        if mt > best_mt:
            best, best_mt = p, mt
    return best


def _mtime(p):
    try:
        return os.path.getmtime(p)
    except OSError:
        return -1.0


def _proc_cwd(pid):
    try:
        return os.readlink("/proc/%d/cwd" % pid)
    except OSError:
        return None


def _find(root, suffix, maxdepth):
    """Walk `root` up to maxdepth levels, yielding files ending in `suffix`."""
    root = root.rstrip("/")
    base_depth = root.count("/")
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        depth = dirpath.count("/") - base_depth
        if depth >= maxdepth:
            dirnames[:] = []
        for fn in filenames:
            if fn.endswith(suffix):
                out.append(os.path.join(dirpath, fn))
    return out


def _strip_tags(t):
    return re.sub(r"<[^>]+>", "", t).strip()


def _open(path):
    # errors="replace" tolerates a partial multibyte sequence captured when a
    # transcript is read mid-write (a UnicodeDecodeError would otherwise blank the
    # whole agent entry for that tick).
    return open(path, encoding="utf-8", errors="replace")


_PCACHE = {}


def _cached(name, src, compute):
    """Memoize a parser result keyed on (src, mtime(src)) so we only do the heavy
    parse when the agent's session file actually changes. `src` is the path the
    result derives from (transcript or db); `compute` is a no-arg parse closure."""
    if not src:
        return {}
    try:
        mt = os.path.getmtime(src)
    except OSError:
        return compute()
    hit = _PCACHE.get(name)
    if hit is not None and hit[0] == src and hit[1] == mt:
        return hit[2]
    val = compute()
    _PCACHE[name] = (src, mt, val)
    return val


def _hyprlock_payload(last_user, last_assistant):
    """Build the lock screen's typewriter-ready payload (a short user line + the
    assistant reply word-wrapped to width 55) from an agent's latest messages.

    This is the JRPG-dialogue filtering that used to live inside the claude-only
    lock-screen script, lifted out verbatim so EVERY agent gets the same payload —
    that's what lets hyprlock show codex/gemini/opencode in the box, not just claude.
    Returns {} when there's nothing displayable."""
    hl = {}
    if last_user:
        u = last_user.replace("\n", " ").strip()
        if len(u) > 49:
            u = u[:46] + "..."
        hl["user"] = u
    if last_assistant:
        parts = []
        total = 0
        for l in last_assistant.split("\n"):
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
            hl["lines"] = textwrap.wrap(text, width=55, break_long_words=True, break_on_hyphens=True)
    return hl


def _claude_session(cwd):
    """Resolve the transcript for the claude session running in `cwd` (its project
    slug = cwd with '/' and '.' -> '-'), so parallel sessions in different projects
    don't cross-contaminate. Falls back to the globally-newest transcript if the cwd
    can't be resolved. Returns the parse (latest user/assistant + hyprlock payload),
    replicating the original lock-screen parse byte-for-byte."""
    transcript = None
    if cwd:
        slug = re.sub(r"[/.]", "-", cwd)
        transcript = _newest(_find(os.path.join(HOME, ".claude", "projects", slug), ".jsonl", 1))
    if not transcript:
        transcript = _newest(_find(os.path.join(HOME, ".claude", "projects"), ".jsonl", 2))
    if not transcript:
        return {}
    return _cached(transcript, transcript, lambda: _claude_parse(transcript))


def _claude_parse(transcript):
    last = None
    last_user = None
    try:
        with _open(transcript) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    data = json.loads(line)
                except json.JSONDecodeError:
                    continue
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
                        clean = _strip_tags(t)
                        if not clean or clean[0] == "#":
                            continue
                        last_user = clean
                if data.get("type") == "assistant":
                    for block in (data.get("message", {}).get("content") or []):
                        if isinstance(block, dict) and block.get("type") == "text":
                            t = block.get("text", "").strip()
                            if t:
                                t = _strip_tags(t)
                                if t:
                                    last = t
    except (OSError, ValueError):
        return {}

    out = {"transcript": transcript}
    if last_user:
        out["lastUser"] = last_user
    if last:
        out["lastAssistant"] = last
    return out


_CODEX_CWD = {}  # rollout path -> cwd (recorded once in session_meta; immutable)


def _codex_rollout_cwd(path):
    """The cwd a codex rollout was started in (from its session_meta header line).
    Cached per path since it never changes for a given rollout file."""
    hit = _CODEX_CWD.get(path)
    if hit is not None:
        return hit
    cwd = ""
    try:
        with _open(path) as f:
            obj = json.loads(f.readline())
        if obj.get("type") == "session_meta":
            cwd = (obj.get("payload") or {}).get("cwd") or ""
    except (OSError, ValueError):
        cwd = ""
    _CODEX_CWD[path] = cwd
    return cwd


def _codex_session(cwd):
    """Resolve the codex rollout for the session running in `cwd` by matching the cwd
    each rollout records in its session_meta header — so parallel codex sessions show
    their own messages. Falls back to the newest rollout globally."""
    rollouts = _find(os.path.join(HOME, ".codex", "sessions"), ".jsonl", 5)
    if not rollouts:
        return {}
    rollouts.sort(key=_mtime, reverse=True)
    transcript = None
    if cwd:
        for r in rollouts[:60]:  # newest-first; bound the per-tick cwd scan
            if _codex_rollout_cwd(r) == cwd:
                transcript = r
                break
    if not transcript:
        transcript = rollouts[0]
    return _cached(transcript, transcript, lambda: _codex_parse(transcript))


def _codex_parse(transcript):
    last_user = None
    last_assistant = None
    try:
        with _open(transcript) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    data = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if data.get("type") != "response_item":
                    continue
                payload = data.get("payload", {})
                if payload.get("type") != "message":
                    continue
                role = payload.get("role")
                text = "".join(
                    b.get("text", "") for b in payload.get("content", [])
                    if isinstance(b, dict) and b.get("text")
                ).strip()
                if not text:
                    continue
                text = _strip_tags(text)
                if role == "assistant":
                    last_assistant = text
                elif role == "user" and not text.startswith("<"):
                    last_user = text
    except (OSError, ValueError):
        return {}
    # Per-session parse: the rollout's own user messages (the `<...>` env-injection
    # filter above keeps genuine prompts), NOT the global history.jsonl — that would
    # be wrong when several codex sessions run at once.
    out = {}
    if last_user:
        out["lastUser"] = last_user
    if last_assistant:
        out["lastAssistant"] = last_assistant
    if transcript:
        out["transcript"] = transcript
    return out


def _gemini_session(cwd):
    """Resolve the gemini chat transcript for `cwd` — gemini keys sessions under
    ~/.gemini/tmp/<cwd-basename>/chats/. Falls back to the newest chat globally."""
    root = os.path.join(HOME, ".gemini", "tmp")
    transcript = None
    if cwd:
        base = os.path.basename(cwd.rstrip("/"))
        transcript = _newest(_find(os.path.join(root, base, "chats"), ".json", 1))
    if not transcript:
        sessions = [p for p in _find(root, ".json", 4) if "/chats/" in p]
        transcript = _newest(sessions)
    if not transcript:
        return {}
    return _cached(transcript, transcript, lambda: _gemini_parse(transcript))


def _gemini_parse(transcript):
    last_user = None
    last_assistant = None
    try:
        # gemini stores the whole conversation as one JSON object — json.load has
        # no streaming bound, so cap the file size to stay under MemoryMax.
        if os.path.getsize(transcript) > 8 * 1024 * 1024:
            return {"transcript": transcript}
        with _open(transcript) as f:
            data = json.load(f)
    except (OSError, ValueError):
        return {}
    for msg in data.get("messages", []):
        mtype = msg.get("type")
        content = msg.get("content")
        if mtype == "user":
            if isinstance(content, list):
                text = "".join(b.get("text", "") for b in content if isinstance(b, dict)).strip()
            else:
                text = str(content or "").strip()
            if text:
                last_user = _strip_tags(text)
        elif mtype == "gemini":
            text = content if isinstance(content, str) else ""
            if text and text.strip():
                last_assistant = _strip_tags(text)
    out = {"transcript": transcript}
    if last_user:
        out["lastUser"] = last_user
    if last_assistant:
        out["lastAssistant"] = last_assistant
    return out


def opencode_status():
    base = os.path.join(HOME, ".local", "share", "opencode", "opencode.db")
    if not os.path.exists(base):
        return {}
    # cache on whichever of the db / its WAL was written most recently
    src = _newest([base, base + "-wal"]) or base
    return _cached("opencode", src, lambda: _opencode_parse(base))


def _opencode_parse(db):
    # mode=ro (NOT immutable=1): opencode is WAL-mode and keeps a live writer, so
    # immutable would ignore the -wal and return stale (checkpointed-only) messages
    # exactly during active use. mode=ro honours the WAL and stays read-only.
    uri = "file:%s?mode=ro" % db
    try:
        conn = sqlite3.connect(uri, uri=True, timeout=1.0)
    except sqlite3.Error:
        return {}
    out = {}
    try:
        cur = conn.cursor()

        def latest(role):
            # bounded scan (no index on time_created); 200 recent rows is plenty to
            # find the latest non-empty message of a role.
            cur.execute("SELECT id, data FROM message ORDER BY time_created DESC LIMIT 200")
            for mid, data in cur:
                try:
                    meta = json.loads(data)
                except (json.JSONDecodeError, TypeError):
                    continue
                if meta.get("role") != role:
                    continue
                cur2 = conn.cursor()
                cur2.execute(
                    "SELECT data FROM part WHERE message_id=? ORDER BY time_created", (mid,)
                )
                texts = []
                for (pdata,) in cur2:
                    try:
                        p = json.loads(pdata)
                    except (json.JSONDecodeError, TypeError):
                        continue
                    if p.get("type") == "text" and p.get("text"):
                        texts.append(p["text"])
                joined = "".join(texts).strip()
                if joined:
                    return joined
            return None

        u = latest("user")
        a = latest("assistant")
        if u:
            out["lastUser"] = _strip_tags(u)
        if a:
            out["lastAssistant"] = _strip_tags(a)
    except sqlite3.Error:
        return out
    finally:
        conn.close()
    return out


# claude/gemini/codex are cwd-keyed, so each running session is resolved to its own
# transcript (claude by project-slug dir, gemini by cwd-basename, codex by the cwd
# recorded in each rollout's session_meta). opencode keeps no per-session cwd index,
# so its displayed message is the newest session's (sessions[] still lists every pid).
SESSION_PARSERS = {"claude": _claude_session, "gemini": _gemini_session, "codex": _codex_session}
NEWEST_PARSERS = {"opencode": opencode_status}

# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

def build(procs):
    """Assemble the agents dict, handling parallel sessions: each running pid is
    listed in `sessions[]` with its cwd. For claude/gemini each session's messages
    are matched by cwd, and the top-level lastUser/lastAssistant/hyprlock reflect the
    most-recently-active session. Parsers self-cache on session-file mtime, so a
    running-but-idle agent costs almost nothing per tick."""
    agents = {}
    active = None
    for name in ("claude", "codex", "gemini", "opencode"):
        pids = sorted(procs.get(name, []))
        running = bool(pids)
        entry = {"running": running, "count": len(pids), "pids": pids}
        if running:
            if active is None:
                active = name
            sessions = [{"pid": pid, "cwd": _proc_cwd(pid)} for pid in pids]
            if name in SESSION_PARSERS:
                parsed = {}
                for s in sessions:
                    try:
                        parsed[s["pid"]] = SESSION_PARSERS[name](s["cwd"]) or {}
                    except Exception:
                        parsed[s["pid"]] = {}  # one bad session must not break others
                # compact per-session view (omit the bulky hyprlock payload here)
                for s in sessions:
                    p = parsed[s["pid"]]
                    for k in ("transcript", "lastUser", "lastAssistant"):
                        if p.get(k):
                            s[k] = p[k]
                # top-level = the most-recently-active session's full parse (+hyprlock)
                best = max((pid for pid, p in parsed.items() if p.get("transcript")),
                           key=lambda pid: _mtime(parsed[pid]["transcript"]), default=None)
                if best is not None:
                    entry.update(parsed[best])
            else:
                try:
                    entry.update(NEWEST_PARSERS[name]())
                except Exception:
                    pass  # one bad parser must never take the daemon down
            entry["sessions"] = sessions
            # Per-agent lock-screen payload, built uniformly from the agent's latest
            # messages — this is what lets hyprlock render any agent in the JRPG box.
            hl = _hyprlock_payload(entry.get("lastUser"), entry.get("lastAssistant"))
            if hl:
                entry["hyprlock"] = hl
        agents[name] = entry
    return agents, active


def _rep_mtime(name, entry):
    """A running agent's 'last activity' time, used to pick the lock-screen speaker.
    Prefer its session transcript's mtime; opencode keeps no transcript path, so fall
    back to its sqlite db (or WAL) mtime."""
    t = entry.get("transcript")
    if t:
        return _mtime(t)
    if name == "opencode":
        return max(_mtime(OPENCODE_DB), _mtime(OPENCODE_DB + "-wal"))
    return 0.0


def _flat_sessions(agents):
    """Every running session across all agents, flattened into one list ordered
    most-recently-active first, each tagged with its agent + working directory and
    its own lock-screen payload. This is the list the lock screen cycles through.
    A session without its own messages (opencode) falls back to its agent's newest."""
    flat = []
    for name in ("claude", "codex", "gemini", "opencode"):
        a = agents[name]
        if not a.get("running"):
            continue
        agent_hl = a.get("hyprlock") or {}
        for s in a.get("sessions", []):
            su, sa = s.get("lastUser"), s.get("lastAssistant")
            hl = _hyprlock_payload(su, sa) if (su or sa) else agent_hl
            cwd = (s.get("cwd") or "").rstrip("/")
            mt = _mtime(s["transcript"]) if s.get("transcript") else _rep_mtime(name, a)
            e = {"agent": DISPLAY[name],
                 "dir": os.path.basename(cwd) or DISPLAY[name],
                 "cwd": cwd, "_mt": mt}
            if hl.get("user"):
                e["user"] = hl["user"]
            if hl.get("lines"):
                e["lines"] = hl["lines"]
            flat.append(e)
    flat.sort(key=lambda e: e["_mt"], reverse=True)
    for e in flat:
        e.pop("_mt", None)
    return flat


def lockscreen(agents):
    """Top-level lock-screen payload. `sessions` is the cycle-through list (most
    recently active first); the box defaults to sessions[0] — the "speaker". `running`
    is the distinct agent names (speaker's first) for a glance. Returns None when
    nothing is running, so hyprlock hides the box entirely."""
    flat = _flat_sessions(agents)
    if not flat:
        return None
    seen, running = set(), []
    for e in flat:
        if e["agent"] not in seen:
            seen.add(e["agent"])
            running.append(e["agent"])
    head = flat[0]
    out = {"speaker": head["agent"], "running": running, "sessions": flat}
    if head.get("user"):
        out["user"] = head["user"]
    if head.get("lines"):
        out["lines"] = head["lines"]
    return out


def atomic_write(payload):
    tmp = "%s.tmp.%d" % (OUT, os.getpid())
    with open(tmp, "w") as f:
        f.write(payload)
    os.replace(tmp, OUT)


def main():
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    while True:
        try:
            procs = scan_procs()
            agents, active = build(procs)
            doc = {
                "updated": time.strftime("%Y-%m-%dT%H:%M:%S"),
                "updatedNs": str(time.time_ns()),
                "host": HOSTNAME,
                "any": active is not None,
                "active": active,
                "agents": agents,
            }
            hl = lockscreen(agents)
            if hl is not None:
                doc["hyprlock"] = hl
            # Write every tick (cheap tmpfs write) so the file mtime is a reliable
            # heartbeat — consumers use it to tell a live daemon from a dead one.
            # Per-agent parsing is mtime-cached, so an idle tick is nearly free.
            atomic_write(json.dumps(doc))
        except Exception:
            pass  # never die on a transient error; try again next tick
        time.sleep(1)


if __name__ == "__main__":
    main()
