---
title: "feat: Add shellbox Digital Ocean NixOS host"
type: feat
status: active
date: 2026-03-05
origin: docs/brainstorms/2026-03-05-shellbox-droplet-brainstorm.md
---

# feat: Add shellbox Digital Ocean NixOS host

## Overview

Add a new headless NixOS host (`shellbox`) to the nix-config flake, targeting a Digital Ocean droplet. Shellbox is a persistent, always-available multi-agent workspace accessed via SSH. Provisioned with `doctl`, deployed with `nixos-anywhere`, managed through the same flake as thinkpad and macbook-pro.

## Problem Statement / Motivation

There is no persistent remote workspace for running AI agents (Claude Code, etc.) that survives laptop sleep/shutdown. A cloud-hosted NixOS instance gives a stable, always-on environment with the same tooling (neovim, tmux, git, dev-tools) as local machines, managed declaratively through the existing flake.

## Proposed Solution

1. Create `hosts/shellbox/` with host config, disko layout, and hardware config
2. Add `nixosConfigurations.shellbox` to `flake.nix` with headless module selection
3. Add a `headless` flag to `hmConfig` and `home/default.nix` to skip GUI imports
4. Provision a DO droplet via `doctl` and deploy NixOS via `nixos-anywhere`

(see brainstorm: docs/brainstorms/2026-03-05-shellbox-droplet-brainstorm.md)

## Technical Considerations

### Architecture

- **System:** x86_64-linux, BIOS boot (not UEFI), virtio disk/network
- **Disk:** `/dev/vda`, GPT with 1M EF02 (GRUB BIOS boot) + ext4 root
- **Kernel:** Must include `virtio_pci`, `virtio_scsi`, `virtio_blk`, `virtio_net` in initrd
- **Console:** `console=ttyS0` for DO web console access
- **Boot:** GRUB (not Lanzaboote), verbose boot params (override core.nix `quiet`)
- **Network:** DHCP via NetworkManager (override wifi MAC randomization as unnecessary)

### Security

- SSH key-only auth, no password auth, no root login (`prohibit-password` for nixos-anywhere re-runs)
- fail2ban with progressive ban times
- Firewall: port 22 only (override core.nix Syncthing ports via `mkForce`)
- Passwordless sudo kept (Tailscale planned for future hardening layer)

### Key Gotchas

- SSH keys are wiped during nixos-anywhere install — keys MUST be declared in NixOS config
- 2 GB minimum RAM for nixos-anywhere kexec phase
- SSH host key changes after install — run `ssh-keygen -R <ip>` before reconnecting
- Nix store on 25 GB disk fills fast — weekly GC from `modules/shared/nix.nix` handles this
- `agent-context.nix` has hardcoded thinkpad module list — accept inaccuracy for now

## Implementation Steps

### Phase 1: Nix Configuration (local, no droplet needed)

#### 1.1 Create `hosts/shellbox/disko.nix`

Simple GPT layout for DO virtio disk:
- 1M `EF02` BIOS boot partition (NOT `EF00`)
- 512M `EF00` ESP at `/boot` (forward UEFI compat)
- Remaining space: ext4 root at `/`
- Device: `lib.mkDefault "/dev/vda"`

```
hosts/shellbox/disko.nix
```

#### 1.2 Create `hosts/shellbox/hardware-configuration.nix`

Hand-written (not generated) with known DO virtio modules:

```nix
# Key content:
boot.initrd.availableKernelModules = [ "virtio_pci" "virtio_scsi" "virtio_blk" "virtio_net" "ahci" "sd_mod" ];
boot.kernelModules = [ "virtio_pci" "virtio_net" ];
```

Note: Can be regenerated post-install with `nixos-generate-config` if needed.

```
hosts/shellbox/hardware-configuration.nix
```

#### 1.3 Create `hosts/shellbox/default.nix`

Host-specific config:

- `networking.hostName = "shellbox"`
- GRUB bootloader config (`boot.loader.grub.device = "/dev/vda"`, `efiSupport = true`, `efiInstallAsRemovable = true`)
- `boot.kernelParams = [ "console=ttyS0" ]` (override quiet boot from core.nix)
- SSH server: `services.openssh.enable = true`, `PasswordAuthentication = false`, `PermitRootLogin = "prohibit-password"`, `LogLevel = "VERBOSE"`
- SSH authorized keys for `${user}` and `root` (hardcoded public key)
- fail2ban: `services.fail2ban.enable = true`, `maxretry = 5`, `bantime = "1h"`, progressive `bantime-increment`
- zram swap: `zramSwap = { enable = true; algorithm = "zstd"; memoryPercent = 50; }`
- Firewall overrides: `networking.firewall.allowedTCPPorts = lib.mkForce [ 22 ]`, `allowedUDPPorts = lib.mkForce []`
- `system.stateVersion = "25.05"`

```
hosts/shellbox/default.nix
```

#### 1.4 Add `headless` flag to `hmConfig` in `flake.nix`

Modify `hmConfig` to accept a `headless` parameter:

```nix
# Before:
hmConfig = system: { ... extraSpecialArgs = { inherit inputs user system; ... }; };

# After:
hmConfig = system: { headless ? false }: { ... extraSpecialArgs = { inherit inputs user system headless; ... }; };
```

Existing callers pass `(hmConfig system {})` or `(hmConfig system { headless = false; })`.
Shellbox passes `(hmConfig system { headless = true; })`.

```
flake.nix (lines ~60-68)
```

#### 1.5 Gate Linux GUI imports in `home/default.nix`

```nix
# Before (line 15):
] ++ lib.optionals isLinux [ ./linux ]

# After:
] ++ lib.optionals (isLinux && !headless) [ ./linux ]
```

Add `headless ? false` to the function arguments.

```
home/default.nix (lines 1, 15)
```

#### 1.6 Add `nixosConfigurations.shellbox` to `flake.nix`

```nix
nixosConfigurations.shellbox = let system = "x86_64-linux"; in nixpkgs.lib.nixosSystem {
  specialArgs = { inherit inputs user; unstable = unstableFor system; };
  modules = [
    { nixpkgs.hostPlatform = system; }
    disko.nixosModules.disko
    ./hosts/shellbox/default.nix
    ./hosts/shellbox/disko.nix
    ./modules/shared/nix.nix
    ./modules/nixos/core.nix
    ./modules/nixos/agent-context.nix
    home-manager.nixosModules.home-manager
    (hmConfig system { headless = true; })
  ];
};
```

No lanzaboote, no nvidia, no hyprland, no power, no stylix, no greetd, no nixos-hardware.

```
flake.nix (after thinkpad block, ~line 99)
```

#### 1.7 Add flake check for shellbox

```nix
checks.x86_64-linux.shellbox = nixosConfigurations.shellbox.config.system.build.toplevel;
```

```
flake.nix (checks block)
```

#### 1.8 Validate config builds

```bash
nix build .#nixosConfigurations.shellbox.config.system.build.toplevel --dry-run
```

This verifies the config evaluates without errors. No droplet needed.

### Phase 2: Provision Droplet with doctl

#### 2.1 Ensure doctl is authenticated

```bash
doctl auth init  # paste DO API token if not already configured
```

#### 2.2 Upload SSH key to DO (if not already)

```bash
doctl compute ssh-key import shellbox-key --public-key-file ~/.ssh/id_ed25519.pub
doctl compute ssh-key list  # note the key ID or fingerprint
```

#### 2.3 Create the droplet

```bash
doctl compute droplet create shellbox \
  --image ubuntu-24-04-x64 \
  --size s-2vcpu-2gb \
  --region nyc1 \
  --ssh-keys <key-id-or-fingerprint> \
  --wait
```

- `s-2vcpu-2gb`: 2 vCPU, 2 GB RAM, 50 GB SSD — ~$18/mo
- Ubuntu base image is temporary — nixos-anywhere replaces it entirely
- `--wait` blocks until droplet is ready

#### 2.4 Get droplet IP

```bash
doctl compute droplet list --format ID,Name,PublicIPv4
```

### Phase 3: Deploy NixOS with nixos-anywhere

#### 3.1 Run nixos-anywhere

```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake ~/nix-config#shellbox \
  --target-host root@<droplet-ip>
```

This will: kexec into NixOS installer → run disko → install NixOS → reboot.

#### 3.2 Fix SSH known hosts

```bash
ssh-keygen -R <droplet-ip>
```

#### 3.3 Verify access

```bash
ssh javels@<droplet-ip>
# Should land in a shell with your neovim/tmux/git/dev-tools config
```

#### 3.4 Verify system health

```bash
ssh javels@<droplet-ip> "systemctl is-system-running && cat /etc/agent-context.md"
```

### Phase 4: Post-Deploy Verification

- [ ] SSH login works with key auth
- [ ] `hostname` returns `shellbox`
- [ ] `systemctl is-system-running` returns `running`
- [ ] fail2ban is active: `systemctl status fail2ban`
- [ ] Firewall only allows SSH: `sudo iptables -L -n`
- [ ] zram swap is active: `swapon --show`
- [ ] Auto-upgrade timer exists: `systemctl list-timers | grep nixos-upgrade`
- [ ] Home-manager tools work: `nvim --version`, `tmux -V`, `git --version`
- [ ] No GUI packages installed: `which hyprland` returns not found

## Acceptance Criteria

- [x] `hosts/shellbox/` directory with `default.nix`, `disko.nix`, `hardware-configuration.nix`
- [x] `nixosConfigurations.shellbox` in `flake.nix` with headless module subset
- [x] `headless` flag in `hmConfig` and `home/default.nix` gating `home/linux/` imports
- [x] Flake check passes: `nix flake check --system x86_64-linux`
- [x] Existing thinkpad and macbook-pro configs unaffected (backward compatible)
- [ ] DO droplet provisioned and NixOS deployed via nixos-anywhere
- [ ] SSH access works, system is running, all Phase 4 checks pass

## Dependencies & Risks

**Dependencies:**
- Digital Ocean account with API token
- `doctl` installed on Mac (available via Homebrew or nix)
- `nixos-anywhere` (fetched via `nix run`, no install needed)
- SSH key pair on Mac

**Risks:**
- **Boot failure on first deploy:** Wrong disko layout or missing virtio modules. Mitigate by dry-building first and using `console=ttyS0` for DO web console debugging.
- **Lockout after nixos-anywhere:** SSH keys not in NixOS config. Mitigate by verifying keys are declared in `hosts/shellbox/default.nix` before deploying.
- **Nix store fills 50 GB disk:** Weekly GC from `nix.nix` mitigates. Monitor with `df -h /nix`.
- **core.nix changes break shellbox:** mkForce overrides could drift. TODO: refactor core.nix into shared/workstation split.

## Future Work (deferred)

- Tailscale VPN for private networking (see brainstorm)
- Docker for containerized agent tools/MCP servers (see brainstorm)
- Refactor `modules/nixos/core.nix` into `core-base.nix` + `core-desktop.nix`
- Parameterize `modules/nixos/agent-context.nix` for multi-host accuracy
- `apps/provision-shellbox` script for reproducible provisioning
- Monitoring/alerting for droplet health
- Gate `home/common/kitty.nix` behind headless flag (~150 MB unnecessary on server)
- Auto `nix flake update` before auto-upgrade for security patches

## Sources & References

### Origin

- **Brainstorm document:** [docs/brainstorms/2026-03-05-shellbox-droplet-brainstorm.md](docs/brainstorms/2026-03-05-shellbox-droplet-brainstorm.md) — Key decisions carried forward: headless flag approach, module selection, standard security hardening, zram swap, Tailscale/Docker deferred.

### Internal References

- Thinkpad host pattern: `hosts/thinkpad/default.nix`
- Thinkpad disko: `hosts/thinkpad/disko.nix`
- hmConfig function: `flake.nix:60-68`
- Home-manager entry: `home/default.nix:15`
- Core module: `modules/nixos/core.nix`
- Agent context: `modules/nixos/agent-context.nix`
- Existing server TODO: `flake.nix:124`

### External References

- nixos-anywhere quickstart: https://nix-community.github.io/nixos-anywhere/quickstart.html
- nixos-anywhere examples: https://github.com/nix-community/nixos-anywhere-examples
- disko documentation: https://github.com/nix-community/disko
- NixOS DO config module: https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/digital-ocean-config.nix
- doctl reference: https://docs.digitalocean.com/reference/doctl/reference/compute/droplet/create/
- NixOS fail2ban wiki: https://wiki.nixos.org/wiki/Fail2ban
