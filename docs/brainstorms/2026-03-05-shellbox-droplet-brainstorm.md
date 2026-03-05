# Brainstorm: Shellbox - Digital Ocean NixOS Agent Workspace

**Date:** 2026-03-05
**Status:** Draft

## What We're Building

A persistent Digital Ocean droplet running NixOS, managed as a new host (`shellbox`) in the nix-config repo. It serves as an always-available multi-agent hub -- a headless workspace for running Claude Code, other AI agents, and supporting services over SSH.

**Target specs:**
- Digital Ocean droplet, small tier (2-4 GB RAM)
- NixOS, x86_64-linux, headless (no GUI)
- Deployed via nixos-anywhere over SSH
- Hostname: `shellbox`

## Why This Approach

A NixOS droplet managed through the existing flake gives us:
- **Declarative, reproducible infrastructure** -- the droplet config is version-controlled alongside the other hosts
- **Shared tooling** -- same neovim, tmux, git, shell config as the other machines via home-manager common modules
- **nixos-anywhere deployment** -- proven remote install workflow, uses disko for disk layout, no manual setup
- **Minimal maintenance** -- system updates via `nixos-rebuild switch` from the flake

## Key Decisions

### 1. Host structure follows existing patterns
- `hosts/shellbox/default.nix` -- hostname, SSH, security hardening, stateVersion
- `hosts/shellbox/hardware-configuration.nix` -- generated post-install
- `hosts/shellbox/disko.nix` -- simple disk layout for DO (no LUKS, no Btrfs subvolumes needed)
- New `nixosConfigurations.shellbox` block in `flake.nix`

### 2. Module selection: headless subset
Include:
- `modules/shared/nix.nix` -- flake settings, caches, gc
- `modules/nixos/core.nix` -- base system, networking, firewall, user, sudo, packages
- `modules/nixos/agent-context.nix` -- agent metadata

Skip (GUI/laptop-only):
- `audio.nix`, `nvidia.nix`, `hyprland.nix`, `power.nix`, `stylix.nix`, `greetd.nix`
- Lanzaboote (no secure boot on a VM)
- nixos-hardware (no physical hardware quirks)

### 3. Headless flag for home-manager
- Add `headless` variable to `specialArgs` (default `false`)
- Pass through to home-manager via `extraSpecialArgs`
- `home/default.nix` gates Linux GUI imports (`home/linux/`) behind `isLinux && !headless`
- Common modules (shell, git, neovim, tmux, dev-tools) apply to all hosts including shellbox

### 4. Security: standard hardening
- SSH key-only authentication (no passwords)
- Firewall: allow SSH (port 22) only
- fail2ban enabled
- No root login over SSH
- Passwordless sudo for wheel user (matches existing core.nix default)

### 5. Services (initial)
- **SSH server** -- Primary access method
- **Auto-upgrade** -- Scheduled rebuild from github:jvall0228/nix-config/main (same as thinkpad)
- **zram swap** -- Compressed in-memory swap to handle memory pressure on small VM

**Deferred (add later):**
- Tailscale VPN for mesh networking
- Docker for containerized agent tools/MCP servers

### 6. Deployment: nixos-anywhere
- Create DO droplet with any base image (Ubuntu/Debian)
- Run `nixos-anywhere --flake .#shellbox root@<droplet-ip>` to install NixOS remotely
- disko handles disk partitioning during install
- Post-install: push SSH keys, apply config

## Resolved Questions

1. **Auto-upgrade** -- Yes, auto-upgrade from GitHub repo like thinkpad.
2. **Swap** -- zram swap for compressed in-memory swap on the small VM.
3. **Tailscale/Docker** -- Deferred to a follow-up iteration. Start with SSH-only access.

## Scope Boundaries

**In scope:**
- New host directory (`hosts/shellbox/`) and flake config
- Headless flag mechanism in home-manager
- Basic disko config for DO
- Security hardening (SSH, firewall, fail2ban)
- zram swap configuration
- Auto-upgrade from GitHub
- nixos-anywhere deployment instructions

**Out of scope (for now):**
- Tailscale VPN
- Docker
- MCP server configurations
- Agent orchestration tooling
- Monitoring/alerting
- Backup strategy
- Multi-user access
