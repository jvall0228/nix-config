---
title: "feat: Make NixOS environment ergonomic for AI agents"
type: feat
status: completed
date: 2026-03-02
---

# feat: Make NixOS environment ergonomic for AI agents

## Enhancement Summary

**Deepened on:** 2026-03-02
**Research agents used:** security-sentinel, architecture-strategist, agent-native-reviewer, code-simplicity-reviewer, best-practices-researcher, Context7 NixOS Wiki

### Key Changes from Original Plan
1. **Dramatically simplified** — replaced 10 scoped NOPASSWD rules with `wheelNeedsPassword = false` (one line). On a personal LUKS-encrypted workstation, scoped rules provide security theater: `nixos-rebuild switch` itself is already arbitrary root code execution.
2. **Removed `trusted-users`** — research confirms it is "essentially equivalent to giving root access" (NixOS docs). Since `wheelNeedsPassword = false` already grants passwordless sudo, `trusted-users` adds no value — all nix daemon operations work fine via `sudo nix ...`.
3. **Dropped YAGNI scripts** — `apps/dry-build` (doesn't need sudo, works today), `apps/rollback` (recovery action for humans), parameterized `apps/clean` (hardcoded 7d is fine).
4. **Kept what matters** — absolute flake path fix in `apps/build-switch`, CLAUDE.md agent docs, TTY-safe output.

### Security Research Findings
- Sudoers wildcards (`nixos-rebuild switch *`) allow arbitrary flake execution from any URI — a critical privilege escalation path ([Compass Security](https://blog.compass-security.com/2012/10/dangerous-sudoers-entries-part-4-wildcards/))
- `systemctl restart *` grants control over security-critical services (journald, dbus, logind)
- `trusted-users` allows `--option post-build-hook /tmp/evil.sh` which runs as root ([NixOS GitHub #231408](https://github.com/NixOS/nixpkgs/issues/231408))
- `${pkgs.foo}/bin/cmd` paths in sudo rules break on package updates due to store hash changes ([NixOS Discourse](https://discourse.nixos.org/t/sudoers-paths-not-working-binary-path-doesnt-match-path-to-containing-package/36689))
- `wheelNeedsPassword = false` is the community-accepted pattern for personal workstations ([NixOS Wiki](https://wiki.nixos.org/wiki/Sudo))

---

## Overview

Claude Code cannot run `sudo` commands unattended because a password is always required. This blocks the most critical agent workflow: editing Nix config and rebuilding the system. This plan enables passwordless sudo, fixes wrapper scripts, and documents agent workflows.

## Problem Statement

Current blockers for agent autonomy:

1. **`sudo` requires password** — `apps/build-switch` calls `sudo nixos-rebuild switch`, which hangs waiting for stdin password input.
2. **`apps/clean` requires password** — `sudo nix-collect-garbage` similarly blocks.
3. **`apps/build-switch` uses relative flake path** — Fails if agent runs from wrong directory.
4. **CLAUDE.md lacks agent workflow docs** — Agent doesn't know which commands are safe or how to recover from failures.

## Proposed Solution

### Phase 1: Passwordless sudo for wheel group

Add one line to `modules/nixos/core.nix`:

```nix
# modules/nixos/core.nix — add after existing security.sudo.execWheelOnly = true;
security.sudo.wheelNeedsPassword = false;
```

**Why this over scoped rules:**
- `nixos-rebuild switch` already grants arbitrary root code execution (you deploy a config that controls the entire system). Scoping sudo to "only nixos-rebuild" provides no real security boundary.
- Scoped rules using `extraRules` are fragile on NixOS — store hash paths change on package updates, symlink resolution mismatches cause silent rule failures ([NixOS Discourse](https://discourse.nixos.org/t/sudoers-paths-not-working/36689)).
- `execWheelOnly = true` (already set) ensures only the wheel-group user can sudo at all.
- LUKS full-disk encryption protects at rest. This is a single-user personal workstation.
- This is the pattern used in the NixOS Wiki for cloud/automation setups.

**Why NOT `trusted-users`:**
- The Nix documentation warns: "Adding a user to trusted-users is essentially equivalent to giving that user root access to the system."
- A trusted user can run `nix build --option post-build-hook /tmp/evil.sh` to execute arbitrary code as root.
- A trusted user can run `nix build --option sandbox false` to disable build isolation.
- A trusted user can override substituters to pull unsigned binaries from attacker-controlled caches.
- Since `wheelNeedsPassword = false` already grants passwordless sudo, the agent can use `sudo nix ...` for any operation that needs daemon trust. `trusted-users` adds attack surface with no benefit.

### Phase 2: Fix wrapper scripts

**`apps/build-switch`** — Fix relative path, add TTY-safe output:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_DIR="$(dirname "$SCRIPT_DIR")"
HOST="${1:-$(hostname)}"

if [[ ! "$HOST" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "Error: Invalid hostname '$HOST'" >&2
  exit 1
fi

echo "Building and switching: $HOST (flake: $FLAKE_DIR)"
sudo nixos-rebuild switch --flake "$FLAKE_DIR#$HOST"
echo "Switch complete."
```

Changes from current:
- Uses `BASH_SOURCE[0]` to resolve absolute flake path (works from any directory)
- Auto-detects hostname via `$(hostname)` instead of hardcoding `thinkpad`
- Removes ANSI color codes (pollute agent output parsing; plain text is universal)

**`apps/clean`** — Fix to use absolute path:

```bash
#!/usr/bin/env bash
set -euo pipefail

echo "Collecting garbage older than 7 days..."
nix-collect-garbage --delete-older-than 7d
sudo nix-collect-garbage --delete-older-than 7d
echo "Garbage collection complete."
```

Changes: removes color codes only. Keeps hardcoded 7d (auto-GC in `nix.nix` already handles 30-day window).

### Phase 3: Update CLAUDE.md

Add agent workflow section:

```markdown
## Agent Workflow (NixOS Operations)

All `sudo` commands are passwordless for the wheel-group user.

- **Rebuild system:** `bash apps/build-switch` (auto-detects hostname, uses absolute flake path)
- **Rebuild specific host:** `bash apps/build-switch thinkpad`
- **Dry-build (no sudo needed):** `nixos-rebuild dry-build --flake /home/${user}/nix-config#thinkpad`
- **Rollback:** `sudo nixos-rebuild switch --rollback`
- **Garbage collect:** `bash apps/clean`
- **Check system health:** `systemctl is-system-running` (no sudo needed)
- **Read build logs on failure:** `journalctl -u nixos-rebuild.service -n 100` or `nix log /nix/store/<drv>`
- **Update flake inputs:** `nix flake update` (no sudo needed)

### Constraints
- **Generation limit:** Lanzaboote limits to 10 bootloader entries. Don't apply 10+ broken configs without fixing.
- **Auto-upgrade:** Runs at 04:00 from `github:jvall0228/nix-config/main`. Local uncommitted changes will be overwritten. Commit and push before expecting persistence.
- **State version:** Never change `system.stateVersion` or `home.stateVersion` (currently `25.05`).
```

### Phase 4: Wire up

No new module needed. One line added to existing `modules/nixos/core.nix`.

## Acceptance Criteria

- [x] `sudo nixos-rebuild switch --flake .#thinkpad` works without password — `modules/nixos/core.nix`
- [x] `sudo nix-collect-garbage --delete-older-than 7d` works without password — `modules/nixos/core.nix`
- [x] `apps/build-switch` uses absolute flake path and works from any directory — `apps/build-switch`
- [x] `apps/build-switch` auto-detects hostname — `apps/build-switch`
- [x] `apps/clean` works without password — `apps/clean`
- [x] CLAUDE.md documents agent workflow — `CLAUDE.md`

## Files to Modify

| File | Action | Description |
|------|--------|-------------|
| `modules/nixos/core.nix` | Modify | Add `wheelNeedsPassword = false` |
| `apps/build-switch` | Modify | Absolute flake path, auto-detect hostname, remove colors |
| `apps/clean` | Modify | Remove colors |
| `CLAUDE.md` | Modify | Add agent workflow section |

## Dependencies & Risks

- **Risk:** First rebuild after this change must be done manually with password (chicken-and-egg). One-time setup.
- **Risk:** autoUpgrade at 04:00 can conflict with agent rebuilds. Mitigated by documenting in CLAUDE.md.
- **Risk:** Lanzaboote limits to 10 generations. Mitigated by documenting the limit.
- **Risk:** `wheelNeedsPassword = false` means any process running as the user can sudo without a password. On a single-user LUKS-encrypted workstation this is acceptable. Would NOT be appropriate for a shared or server system.

## Sources

### Internal References
- `modules/nixos/core.nix:48` — current `security.sudo.execWheelOnly = true`
- `modules/shared/nix.nix:10` — current `trusted-users = [ "root" ]`
- `apps/build-switch` — current rebuild script with relative flake path
- `apps/clean` — current GC script
- `home/common/shell.nix` — `claudex` alias

### External References
- [NixOS Wiki: Sudo](https://wiki.nixos.org/wiki/Sudo) — `wheelNeedsPassword` and `extraRules` patterns
- [NixOS trusted-users root-equivalency warning — GitHub #231408](https://github.com/NixOS/nixpkgs/issues/231408)
- [Sudoers paths not matching on NixOS — Discourse](https://discourse.nixos.org/t/sudoers-paths-not-working-binary-path-doesnt-match-path-to-containing-package/36689)
- [Dangerous Sudoers Entries: Wildcards — Compass Security](https://blog.compass-security.com/2012/10/dangerous-sudoers-entries-part-4-wildcards/)
- [security.sudo.extraRules — MyNixOS](https://mynixos.com/nixpkgs/option/security.sudo.extraRules)
- [nix.settings.trusted-users — MyNixOS](https://mynixos.com/nixpkgs/option/nix.settings.trusted-users)
