---
title: "feat: Agent Knowledge Layer — auto-generated system context for AI agents"
type: feat
status: active
date: 2026-03-02
origin: docs/brainstorms/2026-03-02-agent-ergonomic-nixos-brainstorm.md
---

# feat: Agent Knowledge Layer

## Overview

Eliminate the cold-start problem where AI agents waste 1000–5000 tokens per session rediscovering the NixOS environment. Build a NixOS module that auto-generates a machine-readable system context file on every rebuild (including the 04:00 auto-upgrade), plus pre-built agent commands for common NixOS operations.

This is **Layer 1** of the three-layer agent-ergonomic NixOS system (see brainstorm: `docs/brainstorms/2026-03-02-agent-ergonomic-nixos-brainstorm.md`). Layers 2 (Agent Toolkit) and 3 (Sandboxed Environments) are separate follow-up plans.

## Problem Statement

Validated experimentally on 2026-03-02 across Claude Code, Codex, Gemini CLI, and OpenCode:

- **75–87% of agent steps are redundant discovery** — Codex spends 3 steps, Gemini spends 7 steps, just to find `dev-tools.nix` (a task that should take 1 step)
- **Claude Code fails entirely** without CLAUDE.md for cross-directory tasks (hit permission wall and stalled)
- **OpenCode can't inspect NixOS** because `/nix/store/*` paths are auto-rejected by its permission model
- **Non-deterministic NixOS detection** — Codex sometimes skips OS detection and falls back to generic commands (apt/brew/pip)
- **No dynamic context** — current CLAUDE.md is static and hand-maintained; doesn't reflect actual system state

Pre-loaded context eliminates this non-determinism and redundancy.

## Proposed Solution

### Component 1: NixOS context generator module

**File:** `modules/nixos/agent-context.nix`

A pure config NixOS module using `system.activationScripts` to generate `/etc/agent-context.md` on every `nixos-rebuild switch`. This fires on both manual rebuilds and the 04:00 auto-upgrade.

**Module design** — pure config, matching every other module in this repo (import to enable, remove import to disable):

```nix
# modules/nixos/agent-context.nix
{ config, pkgs, ... }:
{
  system.activationScripts.agentContext.text = ''
    # Context generation script (see Content Schema below)
    # Uses full Nix store paths for all commands
    # Writes to tmpfile, then atomic mv
  '';
}
```

No `mkOption`, no `mkEnableOption`, no `mkIf`. This follows the pattern of `audio.nix` (9 lines), `greetd.nix` (4 lines), and every other module in the repo. Import the module in `flake.nix` to enable it; remove the import to disable it.

**Why no `mkOption`:** Every module in this repo is pure config. Introducing `enable`, `outputPath`, and `extraContext` options would add a new pattern with no precedent and no current use case. There is one host. The output path is `/etc/agent-context.md`. If either changes, a one-line edit is simpler than an options interface.

**Design decisions:**
- `system.activationScripts` (not `apps/build-switch` wrapper) — fires on auto-upgrade too (see brainstorm: Layer 1 design considerations)
- Best-effort execution with journal logging: wrap generation in an `if ! ...; then systemd-cat` pattern so failures appear in `journalctl -t agent-context` without blocking rebuilds or the 04:00 auto-upgrade
- Atomic writes: write to `/etc/agent-context.md.tmp`, then `mv` into place to prevent agents from reading a partially-written file
- File permissions: `0644` root-owned, world-readable — agents run as user and need read access
- Full Nix store paths for all commands: use `${pkgs.pciutils}/bin/lspci`, `${pkgs.coreutils}/bin/uname`, etc. — activation scripts run in a minimal environment where bare command names may not be on `PATH`
- `/etc/agent-context.md` is a real file (not a Nix store symlink) written by the activation script — this sidesteps OpenCode's `/nix/store/*` path rejection

**Compact summary content schema** (target: ~80 lines, under 2000 tokens):

```markdown
# System Context — <hostname>
Generated: <ISO 8601 timestamp>

## System
- NixOS <version>, <architecture>, kernel <uname -r>
- Flake: ~/nix-config#<hostname>
- GPU: <lspci VGA line, if available>

## Configuration Paths
- Flake entry point: flake.nix
- Host config: hosts/<hostname>/default.nix
- System packages: modules/nixos/core.nix (environment.systemPackages)
- User packages: home/common/dev-tools.nix (home.packages)
- Shell/aliases: home/common/shell.nix
- Desktop/Hyprland: home/linux/hyprland.nix
- Theming: modules/nixos/stylix.nix

## Enabled Modules
<repo-relative file paths of NixOS modules imported for this host>
- modules/nixos/core.nix
- modules/nixos/audio.nix
- modules/nixos/nvidia.nix
- ... (only local modules, not external flake modules)

## System Packages
<environment.systemPackages names, alphabetized>

## User Packages
<home.packages names from home-manager, alphabetized>

## Constraints
- Do NOT edit hardware-configuration.nix manually
- Do NOT change system.stateVersion or home.stateVersion (currently <version>)
- Do NOT hardcode usernames — use the `user` variable (currently "<user>")
- Do NOT add NixOS-specific options in home/common/ (use home/linux/)
- Lanzaboote: 10 bootloader generation limit — run `bash apps/clean` between major rebuild batches
- Auto-upgrade: 04:00 from github:jvall0228/nix-config/main — commit and push before expecting persistence
```

**Schema design rationale (what was removed vs. original and why):**
- **Removed "Agent Operations" section** — static content already in CLAUDE.md's "Agent Workflow" section. Duplicating it creates maintenance divergence risk.
- **Removed "Active Services" section** — requires curation logic to decide what is "notable." Agents can run `systemctl list-units` when they need this.
- **Removed "Flake Inputs" table** — available via `nix flake metadata` on demand. Extracting locked revisions at eval time is fragile.
- **Removed "Hardware" section (except GPU)** — agents rarely need CPU/memory/disk info. Available from `/proc` when needed. GPU kept because it is relevant to nvidia.nix troubleshooting.
- **Removed generation number** — `readlink /run/current-system` reflects the *previous* generation during activation (symlink updates after activation scripts). Timestamp alone provides freshness signal.
- **Added "Configuration Paths" section** — the brainstorm's primary experiment showed file discovery was the #1 bottleneck (75-87% of steps). Mapping intent → file path is the highest-value content.
- **Added "Constraints" with editing rules** — carries forward CLAUDE.md's "Do Not" section so agents reading only the context file still have guardrails.

### Component 2: Agent commands and `apps/` scripts

**Agent commands:** `nix-config/.claude/commands/` — Claude Code slash commands.

**Executable scripts:** `nix-config/apps/` — tool-agnostic scripts usable by all four AI CLIs.

| Command | Claude Code | Shell script | What it does |
|---------|------------|-------------|-------------|
| rebuild | `.claude/commands/rebuild.md` | `apps/build-switch` (exists) | Run `bash apps/build-switch`, verify with `systemctl is-system-running` |
| system-status | `.claude/commands/system-status.md` | `apps/system-status` (**new**) | Read `/etc/agent-context.md`, check `systemctl is-system-running`, show generation info |

**Why only 2 commands (not 5):**
- `dry-build`, `rollback`, and `gc` are already documented in CLAUDE.md's "Agent Workflow" section. Agents already know these commands.
- `gc` as a convenient slash command makes a destructive operation feel routine — contradicts the Layer 2 brainstorm findings about agents running `nix-collect-garbage -d` without asking.
- `rollback` is a recovery action for humans, not a routine agent operation.
- Additional commands can be added in Layer 2 with proper safety gates.

**`apps/system-status`** is a new shell script (not just a Claude command) so all four tools can use it:

```bash
#!/usr/bin/env bash
set -euo pipefail
echo "=== Agent Context ==="
cat /etc/agent-context.md
echo ""
echo "=== System Health ==="
systemctl is-system-running || true
echo ""
echo "=== Current Generation ==="
readlink /run/current-system
```

### Component 3: CLAUDE.md integration

Update the existing CLAUDE.md with a strong, unconditional reference to the generated context:

```markdown
## System Context (Auto-generated)

IMPORTANT: Always read `/etc/agent-context.md` before running system commands or making
configuration changes. This file contains pre-computed system info that eliminates the
need for discovery commands like `uname`, `lspci`, or directory exploration.

Run `bash apps/system-status` for a full system health check including the context file.

Do NOT modify `/etc/agent-context.md` — it is auto-generated on every rebuild.
```

**Why unconditional:** The original plan used conditional language ("read it at the start of sessions that involve system operations"). Review found that agents will inconsistently follow conditional instructions. Making it unconditional ("IMPORTANT: Always read...") ensures agents load the context regardless of how the user phrases their first message.

### Component 4: Multi-tool discoverability

Create `AGENTS.md` in the repo root — a minimal file that all tools can discover when scanning workspace files:

```markdown
# Agent Context

System context for AI agents is at `/etc/agent-context.md`.
Read it before making configuration changes.

For system health: `bash apps/system-status`
For full agent instructions: see `CLAUDE.md`
```

**Why this works:** The brainstorm found that Gemini reads workspace files, Codex checks for specific files, and Claude Code reads CLAUDE.md. A shared `AGENTS.md` in the repo root covers tools that scan workspace files. Claude Code gets the CLAUDE.md reference. This costs one file with a few lines and covers all four tools on day one.

**Not creating CODEX.md, GEMINI.md, OPENCODE.md** — each tool's config format is unconfirmed and these would be speculative. `AGENTS.md` is tool-agnostic.

## Technical Considerations

### Activation script implementation

The script uses a mix of Nix-evaluated values (available at build time via string interpolation in the module) and runtime commands:

**Build-time values** (from `config.*`, interpolated into the script):
- `config.networking.hostName`
- `config.system.nixos.release`
- `config.system.stateVersion`
- Package names from `config.environment.systemPackages` (mapped to `pname` or `name`)

**Runtime values** (commands in the activation script, using full Nix store paths):
- `${pkgs.coreutils}/bin/uname -r` (kernel version)
- `${pkgs.pciutils}/bin/lspci | grep -i vga` (GPU)
- `${pkgs.coreutils}/bin/date -Iseconds` (timestamp)

This dual approach means the context file reflects both the declared configuration and the actual runtime state.

### Failure handling

```bash
if ! /nix/store/.../generate-context.sh; then
  echo "WARNING: agent-context generation failed" | ${pkgs.systemd}/bin/systemd-cat -t agent-context -p warning
fi
```

Failures appear in the journal (`journalctl -t agent-context`) without blocking the rebuild. The previous context file remains intact due to atomic writes.

### Multi-host readiness

The module uses `config.*` introspection, not hardcoded module names. When `proxmox-vm` is added (which skips nvidia/hyprland/power), the same module will generate correct context for that host automatically.

### Home Manager module (deferred)

A `home/common/agent-context.nix` using `home.activation` instead of `system.activationScripts` is deferred until a non-NixOS host exists (macbook or arch). The NixOS module's design (markdown output, schema) is portable to the HM variant when the time comes.

## System-Wide Impact

- **Interaction graph:** `system.activationScripts.agentContext` fires during `nixos-rebuild switch` after system profile switch. No callbacks, no observers, no side effects beyond writing one file.
- **Error propagation:** Failures logged to journal but never block rebuilds. The auto-upgrade at 04:00 is never at risk.
- **State lifecycle risks:** The only persistent state is `/etc/agent-context.md`. If the script fails, the previous version remains (atomic `mv`). No orphaned state possible.
- **API surface parity:** All AI tools get the same context via the same file at `/etc/agent-context.md`. Claude Code gets it via CLAUDE.md reference; other tools via `AGENTS.md` and `apps/system-status`.
- **Security:** File is root-owned 0644 — agents can read but not write. No sensitive information is exposed beyond what is already public in the GitHub repo. Activation script uses Nix store paths for all commands, avoiding `PATH` dependency. No shell injection vectors — all interpolated values are resolved at Nix evaluation time.

## Acceptance Criteria

### Functional

- [x] `modules/nixos/agent-context.nix` exists as a pure config module — `modules/nixos/agent-context.nix`
- [x] Module is imported in `flake.nix` thinkpad config — `flake.nix`
- [ ] `nixos-rebuild switch` generates `/etc/agent-context.md` — activation script
- [x] Generated file is under 100 lines — context budget
- [x] Generated file contains: hostname, NixOS version, kernel, GPU, configuration paths, enabled modules (as repo-relative file paths), packages, constraints — content schema
- [x] Generated file includes timestamp for freshness
- [x] Activation script failure does not block `nixos-rebuild switch` — journal logging
- [x] File is world-readable (0644) — permission check
- [x] Atomic write via tempfile + `mv` — no partial reads
- [x] `.claude/commands/` contains rebuild and system-status commands — `.claude/commands/`
- [x] `apps/system-status` script exists and is executable — `apps/system-status`
- [x] CLAUDE.md has unconditional reference to `/etc/agent-context.md` — `CLAUDE.md`
- [x] `AGENTS.md` exists in repo root — `AGENTS.md`

### Quality Gates

- [x] `nix flake check` passes
- [ ] `bash apps/build-switch` succeeds and generates the context file
- [ ] Manual verification: context file accurately reflects system state
- [ ] Agent smoke test: open Claude Code, ask "what GPU does this system have?" — should find answer in context without running `lspci`

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `modules/nixos/agent-context.nix` | **Create** | Pure config NixOS module with activation script |
| `flake.nix` | Modify | Add `./modules/nixos/agent-context.nix` to thinkpad modules list |
| `CLAUDE.md` | Modify | Add unconditional system context reference |
| `AGENTS.md` | **Create** | Multi-tool context pointer in repo root |
| `apps/system-status` | **Create** | Shell script for system health + context dump |
| `.claude/commands/rebuild.md` | **Create** | Rebuild slash command |
| `.claude/commands/system-status.md` | **Create** | System status slash command |

## Dependencies & Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Activation script bug blocks rebuild/auto-upgrade | High | Journal logging + `|| true` equivalent; test with dry-build first |
| Context file grows beyond token budget | Medium | Hard cap at ~80 lines; schema is deliberately lean |
| `lspci` or other commands missing from activation `PATH` | Medium | Use full Nix store paths (`${pkgs.pciutils}/bin/lspci`) for all commands |
| Agent modifies or deletes generated context file | Low | File is root-owned 0644; CLAUDE.md instructs agents not to modify |
| Agents ignore CLAUDE.md reference and re-discover anyway | Low | Unconditional "IMPORTANT: Always read" language; `AGENTS.md` as fallback |

## Success Metrics

- Agent discovery steps drop from 3–7 to 1–2 per session (re-test brainstorm's "add bun to dev-tools.nix" experiment)
- Claude Code can answer system questions (GPU, packages, modules) without running discovery commands
- Zero auto-upgrade failures caused by the context generator
- All four AI CLIs (Claude Code, Codex, Gemini, OpenCode) can find and use the context

## Implementation Sequence

1. Create `modules/nixos/agent-context.nix` — pure config module with activation script
2. Add module import to `flake.nix` thinkpad config
3. Dry-build to verify no eval errors: `nixos-rebuild dry-build --flake .#thinkpad`
4. Apply: `bash apps/build-switch`
5. Verify `/etc/agent-context.md` exists and is accurate
6. Create `apps/system-status` script
7. Create `.claude/commands/` directory with rebuild and system-status commands
8. Create `AGENTS.md` in repo root
9. Update CLAUDE.md with unconditional context reference
10. Smoke test with each agent tool

## Review Findings Applied

This plan was revised based on a multi-agent review (2026-03-02) using architecture-strategist, agent-native-reviewer, security-sentinel, code-simplicity-reviewer, and learnings-researcher. Key changes from the original plan:

| Finding | Change |
|---------|--------|
| P1: mkOption is YAGNI — no existing module uses custom options | Replaced with pure config module matching repo conventions |
| P1: CLAUDE.md indirection was conditional and unreliable | Made reference unconditional with "IMPORTANT: Always read" |
| P1: Generated context lacked repo structure and editing constraints | Added "Configuration Paths" and expanded "Constraints" sections |
| P2: `services.*` namespace is for daemons, not activation scripts | Dropped namespace entirely (pure config module) |
| P2: Bare command names may not be on PATH during activation | Specified full Nix store paths for all commands |
| P2: Cut commands from 5 to 2 | Kept rebuild + system-status; deferred dry-build, rollback, gc |
| P2: No tool-agnostic equivalent for .claude/commands/ | Added `apps/system-status` shell script |
| P2: Generation number reflects previous gen during activation | Dropped generation number; timestamp only |
| P3: Stale context detection mechanism won't be used by agents | Removed; timestamp provides sufficient freshness signal |
| P3: Hardware/Flake Inputs/Active Services bloated schema | Slimmed to ~80 lines focused on what agents actually need |
| P3: CODEX.md/GEMINI.md/OPENCODE.md were speculative | Replaced with single `AGENTS.md` in repo root |
| P3: Silent failure via `|| true` | Added `systemd-cat` journal logging for discoverability |
| Security: extraContext shell injection risk | Eliminated by dropping mkOption/extraContext entirely |

## Sources

### Origin

- **Brainstorm document:** [docs/brainstorms/2026-03-02-agent-ergonomic-nixos-brainstorm.md](docs/brainstorms/2026-03-02-agent-ergonomic-nixos-brainstorm.md) — Key decisions carried forward: layered approach (start with knowledge layer), markdown output format, activation script regeneration, tool-agnostic design
- **Prior plan (completed):** [docs/plans/2026-03-02-feat-agent-ergonomics-nixos-plan.md](docs/plans/2026-03-02-feat-agent-ergonomics-nixos-plan.md) — Prerequisites completed: passwordless sudo, wrapper script fixes, CLAUDE.md agent workflow section

### Internal References

- `modules/nixos/core.nix` — existing pure config module pattern to follow
- `modules/nixos/audio.nix`, `modules/nixos/greetd.nix` — simplest module examples
- `flake.nix:42-76` — thinkpad module import list
- `CLAUDE.md` — current agent instructions (stable frame)
- `apps/build-switch` — rebuild wrapper referenced by commands
- `home/common/dev-tools.nix` — AI CLIs installed here

### External References

- [system.activationScripts](https://search.nixos.org/options?query=system.activationScripts) — activation script API
