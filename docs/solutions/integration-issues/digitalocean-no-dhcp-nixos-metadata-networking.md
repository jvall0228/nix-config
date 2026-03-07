---
title: "DigitalOcean has no DHCP — NixOS requires metadata-based static networking"
problem_type: integration-issues
component: hosts/do-nixbox
severity: critical
symptoms:
  - "NixOS droplet unreachable after nixos-anywhere deployment"
  - "SSH connection timeout (not refused) post-reboot"
  - "100% ping packet loss to droplet IP"
  - "dhcpcd falls back to IPv4 link-local (169.254.x.x) — no DHCP response"
root_cause: "DigitalOcean does not provide a DHCP server. Network configuration is static via cloud-init metadata at 169.254.169.254. NixOS defaults (dhcpcd) and the official DO module assume DHCP availability."
solution: "cloud-init with DigitalOcean datasource + systemd-networkd (community standard via srvos)"
technologies:
  - nixos
  - digitalocean
  - nixos-anywhere
  - systemd-networkd
  - dhcpcd
  - cloud-init
  - metadata-api
date_solved: "2026-03-05"
time_to_solve: "~2 hours"
confidence: verified
---

# DigitalOcean has no DHCP — NixOS requires metadata-based static networking

## Problem

After deploying NixOS to a DigitalOcean droplet using nixos-anywhere, the droplet is completely unreachable — no SSH, no ping, no network connectivity at all. The system builds and installs successfully, but after reboot the VM has no IP address.

## Investigation Steps

### Attempt 1: NetworkManager + DHCP override

Imported `core.nix` (which enables NetworkManager), then overrode with `lib.mkForce false` and `networking.useDHCP = true`. **Result:** No network. NM was disabled but dhcpcd received no DHCP response.

### Attempt 2: systemd-networkd with DHCP=yes

Switched to explicit systemd-networkd with `DHCP = "yes"` and `IPv6AcceptRA = true`. **Result:** No network. Same root cause.

### Attempt 3: Disabled systemd initrd + plain dhcpcd

Disabled `boot.initrd.systemd.enable` (from core.nix) to eliminate initrd as a variable. Used traditional mkinitrd with dhcpcd. **Result:** No network.

### Attempt 4: Minimal config without core.nix

Removed `core.nix` entirely. Inlined only essential settings with `networking.useDHCP = true`. **Result:** No network.

### Key debugging breakthrough

Pinged the droplet: **100% packet loss**. This ruled out firewall issues — the VM had no IP at all.

Examined Ubuntu's netplan config on a fresh DO droplet:
```yaml
eth0:
  addresses: ["165.227.206.167/20"]  # static, not DHCP
  routes:
    - to: "0.0.0.0/0"
      via: "165.227.192.1"
```

IPs showed `valid_lft forever` — static assignment, not DHCP leases.

### Direct DHCP test

Ran `dhcpcd -4 -T eth0` on an Ubuntu droplet:
```
dhcpcd-10.0.6 starting
eth0: soliciting a DHCP lease
eth0: probing for an IPv4LL address
eth0: using IPv4LL address 169.254.158.83
```

**No DHCP server responded.** dhcpcd fell back to link-local (APIPA).

### Why nixos-anywhere's kexec phase worked

The kexec installer inherits the static IPs from Ubuntu's cloud-init config. It does NOT use DHCP. The network was pre-configured before NixOS took over.

## Root Cause

**DigitalOcean does not operate a DHCP server.** IP assignment is static, managed via cloud-init and the metadata API at `http://169.254.169.254`. Every NixOS networking strategy that relies on DHCP (NetworkManager, dhcpcd, systemd-networkd with DHCP) fails silently — the client waits for a response that never comes, and the interface gets only a link-local address.

The official NixOS DO config module (`nixos/modules/virtualisation/digital-ocean-config.nix`) relies on `networking.useDHCP = true` (the NixOS default). This works when deploying from a DO NixOS image (which has cloud-init pre-configured networking that persists), but fails when using nixos-anywhere (which wipes the disk and loses cloud-init state).

## Solution

Use **cloud-init with the DigitalOcean datasource** — the community-standard approach used by [srvos](https://github.com/numtide/srvos/blob/main/nixos/hardware/digitalocean/droplet.nix) (maintained by the nixos-anywhere author).

`hosts/do-nixbox/do-networking.nix`:
```nix
{ modulesPath, lib, ... }:
{
  imports = [
    (modulesPath + "/virtualisation/digital-ocean-config.nix")
  ];

  networking.useDHCP = lib.mkForce false;
  networking.useNetworkd = true;

  services.cloud-init = {
    enable = true;
    network.enable = true;
    settings = {
      datasource_list = [ "DigitalOcean" ];
      datasource.DigitalOcean = { };
    };
  };
}
```

The `digital-ocean-config.nix` module provides SSH, serial console (`ttyS0`), GRUB on `/dev/vda`, virtio modules, and DO metadata services (hostname, SSH keys, entropy). cloud-init handles network configuration via the DO metadata API.

Additional overrides in `hosts/do-nixbox/default.nix`:
```nix
boot.growPartition = lib.mkForce false;  # disko manages partition layout
virtualisation.digitalOcean.rebuildFromUserData = false;  # flake manages config
```

### Community approaches comparison

| Approach | Used by | Tradeoff |
|---|---|---|
| **cloud-init + systemd-networkd** | srvos, nixos-anywhere maintainer | Adds ~100MB (Python) but handles IPv6, hostname, SSH keys. **Recommended.** |
| Custom metadata fetch service | Our initial attempt | Lean (no Python) but reinvents cloud-init. 153 lines vs 10. |
| Static IP at install time | nixos-infect, nixops | Simple but baked-in — breaks on IP change. |

### Reference issue

[nixos-anywhere-examples #5](https://github.com/nix-community/nixos-anywhere-examples/issues/5) — exact same problem and solution.

## Prevention

### Quick checklist for cloud deployments

- **Always verify DHCP availability first.** Run `dhcpcd -4 -T <iface>` on a test instance. If it falls back to link-local, there's no DHCP.
- **Check `valid_lft` in `ip addr` output.** `forever` = static. A time value = DHCP lease.
- **Check the base image's netplan/networkd config.** Static addresses in cloud-init config confirm no DHCP.
- **Don't trust the NixOS DO module blindly.** It assumes DHCP works, which is only true for pre-built DO NixOS images.
- **Always include `console=ttyS0`** in kernel params for cloud VMs — it's the only way to debug boot failures via the provider's web console.

### Signs of static vs DHCP networking

| Static IP (no DHCP) | DHCP |
|---|---|
| `valid_lft forever` | `valid_lft 3599sec` |
| cloud-init generates `/etc/resolv.conf` | dhcpcd generates `/etc/resolv.conf` |
| `dhcpcd -T` falls back to link-local | `dhcpcd -T` returns real IP |
| Provider docs mention "metadata service" | Provider docs mention "DHCP" |

### Cloud provider kernel modules

| Provider | Required modules |
|---|---|
| DigitalOcean | virtio_pci, virtio_net, virtio_blk, virtio_scsi |
| AWS (KVM) | virtio_pci, virtio_net, virtio_blk, ena |
| Azure (Hyper-V) | hv_netvsc, hv_storvsc |

## Related

### Internal
- Implementation: `hosts/do-nixbox/do-networking.nix`
- Host config: `hosts/do-nixbox/default.nix`
- Plan: `docs/plans/2026-03-05-feat-do-nixbox-digitalocean-host-plan.md`
- Brainstorm: `docs/brainstorms/2026-03-05-do-nixbox-droplet-brainstorm.md`
- TODO — refactor core.nix: `todos/002-pending-p2-refactor-core-nix-shared-workstation.md`

### External
- [NixOS DO config module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/digital-ocean-config.nix) — assumes DHCP, misleading for nixos-anywhere deployments
- [nixos-anywhere quickstart](https://nix-community.github.io/nixos-anywhere/quickstart.html)
- [DO metadata API docs](https://docs.digitalocean.com/reference/api/metadata-api/)
- [disko documentation](https://github.com/nix-community/disko)
