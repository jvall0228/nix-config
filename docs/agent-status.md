---
title: "AI Agent Status Daemon"
type: reference
status: active
date: 2026-06-26
---

# AI Agent Status Daemon

A background user service that answers one question for the whole machine:
**which AI coding agents are running right now, and what are they saying?**

It is the single source of truth that the Hyprland lock screen, the waybar
indicator, and any script/tool can read — none of them re-implement process
detection or transcript parsing.

## Architecture

```
            ┌─────────────────────────────┐
            │  agent-status daemon (1 Hz)  │   home/linux/agent-status-daemon.py
            │  scan /proc → parse sessions │   (pure-stdlib python, systemd user svc)
            └──────────────┬──────────────┘
                           │ atomic write every tick
                           ▼
          $XDG_RUNTIME_DIR/agent-status.json   (canonical status, tmpfs)
              │                  │                      │
       poll/jq │           poll 2s │                jq │
              ▼                  ▼                      ▼
       agent-status CLI    waybar custom/agent   hyprlock JRPG widget
       (humans/scripts)    (purple pill)         (typewriter dialogue)
```

- **Producer:** `home/linux/agent-status.nix` runs `agent-status-daemon.py` as a
  `Type=simple` systemd **user** service bound to `graphical-session.target`. The
  loop scans `/proc`, parses each *running* agent's newest session, and writes the
  JSON atomically (`tmp` + `os.replace`) every second. The file mtime is a
  heartbeat consumers use to tell a live daemon from a dead one.
- **Consumers poll the file.** Deliberately decoupled — the daemon never signals
  or pokes anything, so it can't destabilise a consumer.

## JSON schema (`$XDG_RUNTIME_DIR/agent-status.json`)

```jsonc
{
  "updated":   "2026-06-26T13:26:11",   // human, refreshed each tick
  "updatedNs": "1782494771...",          // ns; heartbeat / staleness checks
  "host":      "thinkpad",
  "any":       true,                      // is any agent running?
  "active":    "claude",                  // first running agent, or null
  "agents": {
    "claude": {
      "running": true,
      "count":   1,
      "pids":    [3697],
      "lastUser":      "…",               // latest human prompt (cleaned)
      "lastAssistant": "…",               // latest assistant text (cleaned)
      "transcript":    "/home/.../<uuid>.jsonl",
      "hyprlock": {                        // claude only — lock-screen payload
        "user":  "truncated ≤49 chars",
        "lines": ["width-55 wrapped", "…"]
      }
    },
    "codex":    { "running": false, "count": 0, "pids": [] },
    "gemini":   { "running": false, "count": 0, "pids": [] },
    "opencode": { "running": false, "count": 0, "pids": [] }
  }
}
```

Message fields are present only for **running** agents (parsing is gated on the
process existing). `hyprlock` is claude-only and reproduces the original
lock-screen parse byte-for-byte (XML-tag stripping, markdown filtering, 600-char
cap, `textwrap.wrap(width=55)`).

## Consuming the status

```sh
agent-status                 # human-readable table
agent-status --json          # raw JSON (jq .)
agent-status claude          # one agent's object
agent-status --watch         # live (watch -n1)

# or read it directly:
jq -r '.agents.claude.running' "$XDG_RUNTIME_DIR/agent-status.json"
jq -r '.active // "none"'      "$XDG_RUNTIME_DIR/agent-status.json"
```

Always tolerate a missing/stale file (daemon down, pre-first-write): treat it as
"nothing running" and degrade gracefully — every existing consumer does.

## Process detection (the important gotcha)

Nix wraps three of the four binaries with `makeCWrapper`, so the running process
`comm` is `.<name>-wrapped`, **not** `<name>` — and `comm` is capped at 15 chars:

| agent    | detection                       | notes                                    |
|----------|---------------------------------|------------------------------------------|
| claude   | comm `== .claude-wrapped`       | 15 chars (verified live)                 |
| codex    | comm `== .codex-wrapped`        | 14 chars                                 |
| opencode | comm `== .opencode-wrapp`       | **truncated** at 15 (`-ed` cut off)      |
| gemini   | `gemini.js` in `/proc/<pid>/cmdline` | runs as `node`, so match the cmdline |

`pgrep -x claude` matches nothing — this is the same bug that hid the lock-screen
widget for months (see [[claude-process-name-nixos]] memory).

## Session/transcript locations

| agent    | store                                                            | format |
|----------|------------------------------------------------------------------|--------|
| claude   | `~/.claude/projects/<slug>/<uuid>.jsonl`                          | JSONL `type:user/assistant`, `.message.content` blocks |
| codex    | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` (+ `history.jsonl`) | JSONL `response_item` → `payload.role/content[].text` |
| gemini   | `~/.gemini/tmp/<project>/chats/session-*.json`                    | single JSON, `messages[]` `type:user/gemini` |
| opencode | `~/.local/share/opencode/opencode.db`                            | SQLite `message`+`part` (read via python stdlib `sqlite3`; no `sqlite3` binary on box) |

Parsers are **mtime-cached** — a running-but-idle agent costs ~nothing per tick.

## Adding a new agent

1. **Detect it** in `scan_procs()` (`agent-status-daemon.py`): add a comm entry to
   `COMM_MATCH`, or a cmdline check for node/script-based CLIs.
2. **Parse it**: add `def <name>_status()` returning `{lastUser, lastAssistant,
   transcript}` (split find-from-parse and wrap in `_cached(name, src, …)`), and
   register it in `PARSERS`. Wrap risky parsing in try/except — the loop must
   never die.
3. Add the name to the agent loop in `build()` and the CLI's allowed-args list.
4. The waybar/CLI pick it up automatically (they iterate `.agents`).

## Design decisions

- **Long-running loop, not oneshot+timer.** A 1 Hz timer would fork/journal-spam
  86k×/day and systemd timer accuracy fights sub-minute cadences. One resident
  process sleeps in `nanosleep` ~99.9% of the time (≈0% CPU).
- **Poll, not signal.** An earlier design had the daemon `pkill -RTMIN+N waybar`
  to push refreshes. Replaced with a 2 s poll so the producer is fully decoupled
  and can never destabilise the bar; 2 s latency is irrelevant for a glanceable
  indicator.
- **Typewriter `ts` stays in the consumer.** The lock-screen typewriter clock
  (`clawd-jrpg-ts`, reset only when displayed text changes) lives in
  `hyprlock.nix`, *not* the daemon — so the animation still types "fresh on lock"
  even though the daemon parses continuously while unlocked.
- **Resource-capped & fail-soft.** `CPUQuota=5%`, `MemoryMax=64M`, `Nice=10`,
  `IOSchedulingClass=idle`, `OOMScoreAdjust=500`; every parser and the loop body
  swallow exceptions and retry next tick.

## Files

| file | role |
|------|------|
| `home/linux/agent-status-daemon.py` | the daemon (detection + parsing + atomic write) |
| `home/linux/agent-status.nix`       | systemd user service + `agent-status` CLI |
| `home/linux/waybar.nix`             | `custom/agent` indicator (polls the JSON) |
| `home/linux/hyprlock.nix`           | JRPG lock-screen widget (consumes the JSON) |
| `modules/nixos/agent-context.nix`   | advertises the daemon in `/etc/agent-context.md` |

## Operating

```sh
systemctl --user status  agent-status     # health
systemctl --user restart agent-status     # after editing the daemon + rebuild
journalctl --user -u agent-status -f       # logs
```
