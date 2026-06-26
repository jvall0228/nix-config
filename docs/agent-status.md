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
  "hyprlock": {                           // top-level lock-screen payload (omitted
    "speaker":  "Codex",                  //   when nothing runs) = sessions[0].
    "running":  ["Codex", "Claude"],      //   distinct agent names (speaker first)
    "user":     "truncated ≤49 chars",    //   sessions[0].user  (default view)
    "lines":    ["width-55 wrapped", "…"], //  sessions[0].lines (default view)
    "sessions": [                          // ALL running sessions, most-active first;
      { "agent": "Codex",  "dir": "web",   //   the lock screen cycles through these.
        "cwd": "/home/javels/web",
        "user": "…", "lines": ["…"] },     //   each session's OWN messages
      { "agent": "Claude", "dir": "nix-config", "cwd": "…", "user": "…", "lines": ["…"] }
    ]
  },
  "agents": {
    "claude": {
      "running": true,
      "count":   2,                        // instance count (parallel sessions)
      "pids":    [3697, 4011],
      "lastUser":      "…",               // most-recently-active session's (cleaned)
      "lastAssistant": "…",
      "transcript":    "/home/.../<uuid>.jsonl",
      "hyprlock": { "user": "…", "lines": ["…"] },  // per-agent (newest session)
      "sessions": [                        // one per running instance, cwd-resolved
        { "pid": 3697, "cwd": "/home/javels/nix-config",
          "transcript": "…", "lastUser": "…", "lastAssistant": "…" },
        { "pid": 4011, "cwd": "/home/javels/notes", "transcript": "…", "lastUser": "…", "lastAssistant": "…" }
      ]
    },
    "codex":    { "running": false, "count": 0, "pids": [] },
    "gemini":   { "running": false, "count": 0, "pids": [] },
    "opencode": { "running": false, "count": 0, "pids": [] }
  }
}
```

Message fields are present only for **running** agents (parsing is gated on the
process existing). Every running agent carries a `hyprlock` payload — the
JRPG-dialogue filtering (XML-tag stripping, markdown filtering, 600-char cap,
`textwrap.wrap(width=55)`) lives in `_hyprlock_payload()` and is applied
uniformly, reproducing the original claude-only parse byte-for-byte.

**Parallel sessions:** `count`/`pids`/`sessions[]` reflect every running *instance*
of an agent — where an instance is a **session-root** process. A single agent
spawns child processes of the same comm (Claude Code runs subagents and a pool of
`cc-daemon` "spare" workers, all `.claude-wrapped`); `scan_procs()` keeps only pids
whose parent isn't another process of the same agent, so those trees collapse into
the one interactive session that owns them instead of showing up as 8 phantom
sessions. Separately-launched sessions (each parented by a shell) stay distinct.
claude (by project-slug dir), gemini (by cwd-basename) **and codex** (by the cwd
recorded in each rollout's `session_meta`) resolve each session to its own
transcript, so `sessions[].lastUser/lastAssistant` are per-instance. opencode
keeps no per-session cwd index, so its sessions share the newest message.

The **top-level `hyprlock`** is what the lock screen reads. `hyprlock.sessions[]`
is every running session across all agents, ordered most-recently-active first,
each with its agent, working `dir`, and own payload — this is the list the lock
screen **cycles** through (Super+`]`/`[`). `speaker`/`user`/`lines` mirror
`sessions[0]` (the default view). The whole object is **absent** when nothing
runs — that absence is the signal hyprlock uses to hide the box (see `.any`).

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
4. The waybar/CLI pick it up automatically (they iterate `.agents`). The lock
   screen does too: `build()` attaches a `hyprlock` payload to every running agent
   and `lockscreen()` considers all of them when choosing the speaker/roster — no
   hyprlock changes needed for a new agent to appear in the box.

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
- **One box, cycled — not stacked boxes.** The JRPG box shows one session at a
  time (default: the most-recently-active, `hyprlock.sessions[0]`) and is **cycled**
  through the rest with Super+`]` / Super+`[`. Keeps the single-dialogue aesthetic
  while making every parallel session reachable. The header shows the current
  session's `<agent> <dir> [n/total]` so each is identifiable; a single session
  renders as just `<agent>`.
- **Cycling mechanics (lock-screen-safe).** hyprlock routes normal keys to the
  password field, so the cycle keys are Hyprland **`bindl`** binds (fire while
  locked) → `clawd-session-cycle` (in `hyprland.nix`), which bumps
  `clawd-session-cursor` and ages the text cache so the next render re-reads. The
  cursor resets to 0 when no agent runs (in `clawd-pgrep-check`), so each lock
  starts at the speaker. One reader (`clawd-jrpg-text` line 1) does the ~1 Hz jq
  and writes flat caches (`clawd-jrpg-head`/`-user`/`-text`); the header & user
  labels just `cat` them, keeping the 30 ms render path fork-free.
- **The box is an `image`, not a `shape`, so it can hide.** hyprlock `shape`s are
  always drawn (an empty bordered box would linger when idle); an `image` can swap
  its source via `reload_cmd`. The box chrome is pre-rendered to PNGs at build time
  (`boxAssets`, ImageMagick) and `reload_cmd` echoes a transparent PNG when `.any`
  is false. Images render in the image category, *under* labels, so the dialogue
  text still draws on top (verified via hyprlock's `zindex`/category order).
- **Per-agent mascots.** The avatar shows the *current session's* agent its own
  animated pixel sprite — Clawd (purple) for claude, a teal blob for codex, a blue
  sparkle-star for gemini, an amber bot for opencode — and swaps as you cycle
  sessions. `clawd-avatar-frame` reads the agent from the head cache, lowercases it,
  and echoes the matching `assets/mascots/<agent>-frame-{0..3}.png` (claude/unknown
  fall back to the original `clawd-frame-*`; idle shows the static portrait). The 4
  frames cycle ~1 fps off the wall clock. Sprites are procedurally generated by
  `home/linux/mascot-gen.sh` (16×16 char-grid → ImageMagick → point-scaled ×20),
  committed under `assets/mascots/` like the Clawd frames. Adding a mascot for a new
  agent = a `case` arm in `clawd-avatar-frame` + its frames in the script.
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
| `home/linux/mascot-gen.sh`          | procedural generator for the per-agent mascot sprites |
| `home/linux/hyprland.nix`           | `clawd-session-cycle` + Super+`]`/`[` cycle binds |
| `modules/nixos/agent-context.nix`   | advertises the daemon in `/etc/agent-context.md` |

## Operating

```sh
systemctl --user status  agent-status     # health
systemctl --user restart agent-status     # after editing the daemon + rebuild
journalctl --user -u agent-status -f       # logs
```

Lock screen: the JRPG box auto-hides when no agent runs. With multiple sessions
(across claude/codex/gemini/opencode), **Super+`]`** cycles to the next session
and **Super+`[`** to the previous — the header shows `<agent> <dir> [n/total]`.
