---
title: "DigitalOcean has no DHCP — NixOS requires metadata-based static networking"
problem_type: integration-issues
component: hosts/shellbox
severity: critical
symptoms:
  - "NixOS droplet unreachable after nixos-anywhere deployment"
  - "SSH connection timeout (not refused) post-reboot"
  - "100% ping packet loss to droplet IP"
  - "dhcpcd falls back to IPv4 link-local (169.254.x.x) — no DHCP response"
root_cause: "DigitalOcean does not provide a DHCP server. Network configuration is static via cloud-init metadata at 169.254.169.254. NixOS defaults (dhcpcd) and the official DO module assume DHCP availability."
solution: "Custom do-networking.nix module: systemd-networkd with link-local bootstrap + oneshot service fetching IP/gateway/DNS from DO metadata API"
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

Custom `hosts/shellbox/do-networking.nix` module that:

1. **Disables DHCP entirely**
```nix
networking.useDHCP = false;
networking.dhcpcd.enable = false;
```

2. **Uses systemd-networkd with link-local only**
```nix
systemd.network.enable = true;
systemd.network.networks."10-do-public" = {
  matchConfig.Name = "en* eth*";
  networkConfig = {
    LinkLocalAddressing = "ipv4";  # Gets 169.254.x.x — enough to reach metadata API
    LLDP = false;
    EmitLLDP = false;
  };
};
```

3. **Fetches real IP from metadata API at boot**
```nix
systemd.services.do-configure-network = {
  after = [ "systemd-networkd.service" ];
  before = [ "network-online.target" "sshd.service" ];
  wantedBy = [ "multi-user.target" ];
  path = with pkgs; [ curl iproute2 jq gawk ];
  # Script: wait for link-local → fetch metadata → apply static IP
};
```

Key parts of the service script:
```bash
# Wait for link-local address
for attempt in $(seq 1 30); do
  ip addr show dev "$IFACE" | grep -q "169.254." && break
  sleep 1
done

# Ensure route to metadata API
ip route add 169.254.169.254/32 dev "$IFACE" 2>/dev/null || true

# Fetch and apply
METADATA=$(curl -sf --retry 5 --retry-delay 2 http://169.254.169.254/metadata/v1.json)
IP=$(echo "$METADATA" | jq -r '.interfaces.public[0].ipv4.ip_address')
GATEWAY=$(echo "$METADATA" | jq -r '.interfaces.public[0].ipv4.gateway')
ip addr flush dev "$IFACE"
ip addr add "$IP/$CIDR" dev "$IFACE"
ip route add default via "$GATEWAY" dev "$IFACE"
```

4. **Signals network-online.target** via a separate `do-network-online` service so SSH and other services wait for metadata config to complete.

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
- Implementation: `hosts/shellbox/do-networking.nix`
- Host config: `hosts/shellbox/default.nix`
- Plan: `docs/plans/2026-03-05-feat-shellbox-digitalocean-host-plan.md`
- Brainstorm: `docs/brainstorms/2026-03-05-shellbox-droplet-brainstorm.md`
- TODO — refactor core.nix: `todos/002-pending-p2-refactor-core-nix-shared-workstation.md`

### External
- [NixOS DO config module](https://github.com/NixOS/nixpkgs/blob/master/nixos/modules/virtualisation/digital-ocean-config.nix) — assumes DHCP, misleading for nixos-anywhere deployments
- [nixos-anywhere quickstart](https://nix-community.github.io/nixos-anywhere/quickstart.html)
- [DO metadata API docs](https://docs.digitalocean.com/reference/api/metadata-api/)
- [disko documentation](https://github.com/nix-community/disko)
